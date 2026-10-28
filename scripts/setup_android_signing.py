"""Create a private local Android release key without replacing existing keys."""
import os
from pathlib import Path
import secrets
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    properties = ROOT / 'android/key.properties'
    key = Path.home() / '.chhaya/signing/chhaya-release.jks'
    if properties.exists() or key.exists():
        print('Existing signing configuration or key preserved; no changes made.')
        return 0
    key.parent.mkdir(parents=True, exist_ok=True)
    password = secrets.token_urlsafe(48)
    # Store the password before invoking keytool so an interruption cannot leave
    # a successfully generated signing key without its recovery credentials.
    with properties.open('x', encoding='utf-8') as output:
        output.write(f'storeFile={key.as_posix()}\nstorePassword={password}\n'
                     f'keyAlias=chhaya\nkeyPassword={password}\n')
    try:
        subprocess.run(['keytool', '-genkeypair', '-noprompt', '-keystore', str(key),
                        '-storetype', 'JKS', '-alias', 'chhaya', '-keyalg', 'RSA',
                        '-keysize', '4096', '-validity', '10000', '-dname', 'CN=Chhaya',
                        '-storepass:env', 'CHHAYA_SIGNING_PASSWORD',
                        '-keypass:env', 'CHHAYA_SIGNING_PASSWORD'],
                       env={**os.environ, 'CHHAYA_SIGNING_PASSWORD': password},
                       check=True, timeout=120, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        if not key.exists():
            properties.unlink()
        print('Signing setup failed. Existing key material was preserved.', file=sys.stderr)
        return 1
    print(f'Release key created: {key}')
    print('Back up that key and android/key.properties together in encrypted offline storage.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
