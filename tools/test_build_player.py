"""Offline boundary tests for dependency cache and archive handling."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

import build_player as builder


class DependencyBoundaries(unittest.TestCase):
    def test_spatial_source_libraries_are_all_verified_before_any_are_imported(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'ROOT', Path(directory)):
            root = Path(directory)
            metadata = root/'native/mpv/patches/source-frame-manifest.json'
            metadata.parent.mkdir(parents=True)
            contract = dict(api_version=2, base_mpv_revision='revision', patch_sha256='patch', private_header_sha256='header')
            metadata.write_text(json.dumps(contract))
            lock = root/'third_party/mpv/source-lock.json'
            lock.parent.mkdir(parents=True)
            lock.write_text('{}')
            names = ['libmpv.so', 'libavcodec.so']
            (lock.parent/'manifest.json').write_text(json.dumps(dict(packaged_libraries=names)))
            source = root/'source'; source.mkdir()
            libraries = []
            for name in names:
                data = ('fixture-'+name).encode()
                (source/name).write_bytes(data)
                libraries.append(dict(name=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
            receipt = dict(candidate='source-frame', api_version=2, mpv_revision='revision', patch_sha256='patch',
                           private_header_sha256='header', source_lock_sha256=builder.digest(lock),
                           packaged_libraries=names, libraries=libraries)
            path = root/'receipt.json'; path.write_text(json.dumps(receipt))
            (source/names[-1]).write_bytes(b'corrupt')
            with self.assertRaisesRegex(RuntimeError, 'differs from its receipt'):
                builder.prepare_source_mpv(source, path)
            self.assertFalse((root/'android').exists())

    def test_spatial_source_receipt_cannot_relabel_the_standard_backend(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'ROOT', Path(directory)):
            root = Path(directory)
            metadata = root/'native/mpv/patches/source-frame-manifest.json'
            metadata.parent.mkdir(parents=True)
            metadata.write_text(json.dumps(dict(api_version=2)))
            manifest = root/'third_party/mpv/manifest.json';manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps(dict(packaged_libraries=['libmpv.so'])))
            receipt = root/'receipt.json';receipt.write_text(json.dumps(dict(candidate='standard')))
            with self.assertRaisesRegex(RuntimeError, 'source/patch contract'):
                builder.prepare_source_mpv(root/'source', receipt)
            self.assertFalse((root/'android').exists())
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


class VariantIdentityBoundaries(unittest.TestCase):
    def test_package_and_label_are_separate_and_presets_restore_after_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'PROJECT', Path(directory)):
            path = Path(directory)/'export_presets.cfg'
            original = b'\r\n'.join([b'package/unique_name="com.wapok.thru3d"\r\npackage/name="Original"']*3)
            path.write_bytes(original)
            with self.assertRaisesRegex(RuntimeError, 'simulated'):
                with builder.variant_export_presets() as identity:
                    self.assertEqual(identity['application_id'], 'com.wapok.thru3d')
                    self.assertEqual(path.read_text().count('package/name="Immivio"'), 3)
                    raise RuntimeError('simulated export failure')
            self.assertEqual(path.read_bytes(), original)
            with builder.variant_export_presets() as identity:
                self.assertEqual(identity['application_id'], 'com.wapok.thru3d')
                self.assertEqual(identity, builder.android_identity())
            self.assertEqual(path.read_bytes(), original)

    def test_existing_signing_override_is_used_without_generating_another_key(self):
        env = {'GODOT_ANDROID_KEYSTORE_RELEASE_PATH': 'base.key',
               'GODOT_ANDROID_KEYSTORE_RELEASE_USER': 'base', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD': 'fixture'}
        with patch.object(builder, 'run') as run:
            self.assertEqual(builder.signing_environment(env), env)
            run.assert_not_called()

    def test_partial_signing_override_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'all GODOT_ANDROID'):
            builder.signing_environment({'GODOT_ANDROID_KEYSTORE_RELEASE_USER': 'only-alias'})

    def test_missing_legacy_key_cannot_silently_create_a_new_identity(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'ROOT', Path(directory)), patch.object(builder, 'run') as run:
            signing = Path(directory)/'artifacts/signing'; signing.mkdir(parents=True)
            (signing/'thru3d-signing.json').write_text(json.dumps({'keystore': str(signing/'missing.key'), 'alias':'legacy','password':'fixture'}))
            with self.assertRaisesRegex(RuntimeError, 'Saved signing key is missing'):
                builder.signing_environment({})
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
