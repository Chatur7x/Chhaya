import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import database_ops


class DatabaseOperationsTest(unittest.TestCase):
    def test_existing_backup_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'backup.dump'
            path.write_bytes(b'previous backup')
            with patch.object(database_ops, 'run') as run:
                with self.assertRaises(FileExistsError):
                    database_ops.backup(path)
                run.assert_not_called()
            self.assertEqual(path.read_bytes(), b'previous backup')

    def test_failed_dump_removes_partial_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'backup.dump'
            def fail(args, **kwargs):
                kwargs['stdout'].write(b'PGDMPpartial')
                raise subprocess.CalledProcessError(1, args)
            with patch.object(database_ops, 'run', side_effect=fail):
                with self.assertRaises(subprocess.CalledProcessError):
                    database_ops.backup(path)
            self.assertFalse(path.exists())

    def test_invalid_dump_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'backup.dump'
            with patch.object(database_ops, 'run'):
                with self.assertRaises(RuntimeError):
                    database_ops.backup(path)
            self.assertFalse(path.exists())

    def test_dump_is_retained_after_success(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'backup.dump'
            def dump(args, **kwargs):
                kwargs['stdout'].write(b'PGDMPtest fixture')
            with patch.object(database_ops, 'run', side_effect=dump), contextlib.redirect_stdout(io.StringIO()):
                database_ops.backup(path)
            self.assertEqual(path.read_bytes(), b'PGDMPtest fixture')

    def test_failed_restore_cleans_up_only_the_disposable_container(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'backup.dump'
            path.write_bytes(b'PGDMPtest fixture')
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                if 'pg_restore' in args:
                    raise subprocess.CalledProcessError(1, args)
            with patch.object(database_ops, 'run', side_effect=run), patch.object(
                database_ops.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
                with self.assertRaises(subprocess.CalledProcessError):
                    database_ops.restore_drill(path)
            container = calls[0][calls[0].index('--name') + 1]
            self.assertTrue(container.startswith('chhaya-restore-drill-'))
            self.assertIn('--network=none', calls[0])
            self.assertEqual(calls[-1], ['docker', 'rm', '--force', '--volumes', container])
            self.assertEqual(path.read_bytes(), b'PGDMPtest fixture')


if __name__ == '__main__':
    unittest.main()
