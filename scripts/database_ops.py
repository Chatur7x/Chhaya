"""Back up Compose PostgreSQL and verify a dump in a disposable isolated server."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=300, cwd=ROOT, **kwargs)


def backup(destination):
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation protects previous backups from accidental replacement.
    created = False
    try:
        with destination.open('xb') as output:
            created = True
            run(['docker', 'compose', 'exec', '-T', 'postgres', 'pg_dump',
                 '-U', 'chhaya', '-d', 'chhaya', '--format=custom',
                 '--no-owner', '--no-acl'], stdout=output)
            output.flush()
            os.fsync(output.fileno())
        with destination.open('rb') as dump:
            if dump.read(5) != b'PGDMP':
                raise RuntimeError('PostgreSQL did not produce a custom-format dump')
    except BaseException:
        if created:
            destination.unlink(missing_ok=True)
        raise
    print(f'Backup created: {destination}')
    print('This dump contains account metadata. Encrypt it before off-host storage.')


def restore_drill(source):
    source = Path(source).resolve(strict=True)
    with source.open('rb') as dump:
        if dump.read(5) != b'PGDMP':
            raise ValueError('Expected a PostgreSQL custom-format dump')
    container = f'chhaya-restore-drill-{uuid.uuid4().hex}'
    started = False
    try:
        # No ports, no network, no production volumes, and no persistent data.
        # Trust auth is confined to this disposable container's Unix socket.
        run(['docker', 'run', '--detach', '--name', container, '--network=none',
             '--tmpfs', '/var/lib/postgresql/data',
             '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:16-alpine'],
            stdout=subprocess.DEVNULL)
        started = True
        deadline = time.monotonic() + 60
        while True:
            ready = subprocess.run(['docker', 'exec', container, 'pg_isready', '-U', 'postgres'],
                                   timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if ready.returncode == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Disposable PostgreSQL did not become ready')
            time.sleep(1)
        with source.open('rb') as dump:
            run(['docker', 'exec', '-i', container, 'pg_restore', '-U', 'postgres',
                 '-d', 'postgres', '--exit-on-error', '--single-transaction',
                 '--no-owner', '--no-acl'], stdin=dump)
        # Check essential tables are queryable; pg_restore also reinstates and
        # validates foreign keys. A successful drill is not a device recovery test.
        run(['docker', 'exec', container, 'psql', '-U', 'postgres', '-d', 'postgres',
             '-v', 'ON_ERROR_STOP=1', '-c',
             'SELECT count(*) AS users FROM users; '
             'SELECT count(*) AS messages FROM messages; '
             'SELECT count(*) AS conversations FROM conversations; '
             'SELECT count(*) AS devices FROM devices;'])
        print('Restore drill passed in an isolated disposable PostgreSQL instance.')
    finally:
        if started:
            run(['docker', 'rm', '--force', '--volumes', container], stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('backup', help='Back up the configured Compose database').add_argument('path')
    commands.add_parser('restore-drill', help='Restore a trusted backup into an isolated disposable container').add_argument('path')
    args = parser.parse_args()
    try:
        if args.command == 'backup':
            backup(args.path)
        else:
            restore_drill(args.path)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Database operation failed: {type(error).__name__}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
