"""Offline boundary tests for dependency cache and archive handling."""
from pathlib import Path
import argparse
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

import build_player as builder


class DependencyBoundaries(unittest.TestCase):
    def test_engine_failure_terminates_a_hung_export_and_keeps_its_log(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'LOGS', Path(directory)):
            started = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, 'Godot reported an error'):
                builder.run([sys.executable, '-u', '-c',
                    'import time; print("ERROR: Export failed"); time.sleep(60)'],
                    log='export.log', timeout=10, fail_on_engine_error=True)
            self.assertLess(time.monotonic()-started, 8)
            self.assertIn('ERROR: Export failed', (Path(directory)/'export.log').read_text())

    def test_silent_hung_command_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'LOGS', Path(directory)):
            started = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                builder.run([sys.executable, '-c', 'import time; time.sleep(60)'], log='silent.log', timeout=0.5)
            self.assertLess(time.monotonic()-started, 8)

    def test_host_sdk_alias_is_preserved_when_real_path_contains_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = root/'Android SDK real'
            ndk, cmake = '30.0.16248370', '4.1.2'
            (actual/f'ndk/{ndk}/build/cmake').mkdir(parents=True)
            (actual/f'ndk/{ndk}/build/cmake/android.toolchain.cmake').touch()
            (actual/f'cmake/{cmake}').mkdir(parents=True)
            alias = root/'sdk'
            try:
                alias.symlink_to(actual, target_is_directory=True)
            except OSError:
                self.skipTest('Host does not permit directory symlinks')
            jdk = root/'jdk'
            (jdk/'bin').mkdir(parents=True)
            (jdk/'bin'/('java.exe' if os.name == 'nt' else 'java')).touch()
            args = argparse.Namespace(sdk=str(alias), java_home=str(jdk), ndk=ndk, cmake=cmake)
            env, observed = builder.environment(args)
            self.assertEqual(observed, alias.absolute())
            self.assertEqual(env['ANDROID_NDK_HOME'], str(alias.absolute()/f'ndk/{ndk}'))
            self.assertTrue((observed/f'ndk/{ndk}/build/cmake/android.toolchain.cmake').is_file())

    def test_zip_traversal_is_rejected_before_extracting_any_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'unsafe.zip'
            with zipfile.ZipFile(archive, 'w') as stream:
                stream.writestr('valid', 'valid')
                stream.writestr('../outside', 'escape')
            with self.assertRaisesRegex(RuntimeError, 'Unsafe dependency archive path'):
                builder.extract(archive, root/'output')
            self.assertFalse((root/'outside').exists())
            self.assertFalse((root/'output/valid').exists())

    def test_zip_symlink_cannot_redirect_a_later_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'unsafe.zip'
            with zipfile.ZipFile(archive, 'w') as stream:
                link = zipfile.ZipInfo('link')
                link.create_system = 3
                link.external_attr = (0o120777 << 16)
                stream.writestr(link, '../outside')
                stream.writestr('link/file', 'escape')
            with self.assertRaisesRegex(RuntimeError, 'symbolic link'):
                builder.extract(archive, root/'output')
            self.assertFalse((root/'outside').exists())

    def test_corrupted_cached_download_is_not_trusted(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'run') as network:
            root = Path(directory)
            (root/'downloads').mkdir()
            path = root/'downloads/library.zip'
            path.write_bytes(b'original bytes')
            record = {'url': 'https://example.invalid/library.zip', 'sha256': builder.digest(path)}
            with patch.object(builder, 'CACHE', root):
                self.assertEqual(builder.download(record, path.name), path)
                path.write_bytes(b'changed bytes')
                with self.assertRaisesRegex(RuntimeError, 'Cached checksum mismatch'):
                    builder.download(record, path.name)
            network.assert_not_called()


if __name__ == '__main__':
    unittest.main()
