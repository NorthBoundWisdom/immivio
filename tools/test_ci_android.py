"""Offline checks for CI template caching and optional signing configuration."""
import base64
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import ci_android as ci


class CiBoundaries(unittest.TestCase):
    def test_templates_install_only_android_and_repair_a_corrupt_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root/'templates'
            files = {'version.txt': b'4.7.2.stable\n', 'android_source.zip': b'android-source-fixture'}
            record = {'files': {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}

            def download(*_):
                archive = root/'all-templates.tpz'
                with zipfile.ZipFile(archive, 'w') as source:
                    for name, data in files.items():
                        source.writestr('templates/'+name, data)
                    source.writestr('templates/linux_release.x86_64', b'not needed')
                return archive

            with patch.object(ci.player, 'download', side_effect=download) as fetch:
                ci.install_android_templates(record, destination)
                self.assertEqual(set(p.name for p in destination.iterdir()), set(files))
                self.assertFalse((root/'all-templates.tpz').exists())
                ci.install_android_templates(record, destination)
                self.assertEqual(fetch.call_count, 1)
                (destination/'android_source.zip').write_bytes(b'corrupted')
                ci.install_android_templates(record, destination)
                self.assertEqual(fetch.call_count, 2)
                self.assertEqual((destination/'android_source.zip').read_bytes(), files['android_source.zip'])

    def test_partial_signing_configuration_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'all three'):
            ci.signing_env({'CI_ANDROID_KEY_ALIAS': 'fixture'})

    def test_optional_signing_is_isolated_from_transport_variables(self):
        with tempfile.TemporaryDirectory() as directory:
            source = {'RUNNER_TEMP': directory, 'CI_ANDROID_KEYSTORE_BASE64': base64.b64encode(b'fixture key').decode(),
                      'CI_ANDROID_KEY_ALIAS': 'fixture', 'CI_ANDROID_KEY_PASSWORD': 'fixture-password'}
            env, mode = ci.signing_env(source)
            self.assertEqual(mode, 'repository-signing-key')
            self.assertFalse(any(name.startswith('CI_ANDROID_') for name in env))
            self.assertEqual(Path(env['GODOT_ANDROID_KEYSTORE_RELEASE_PATH']).read_bytes(), b'fixture key')
            self.assertEqual(env['GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD'], 'fixture-password')
            self.assertNotIn('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', source)

    def test_missing_signing_secrets_uses_ephemeral_ci_mode(self):
        env, mode = ci.signing_env({})
        self.assertEqual(mode, 'ephemeral-ci-key')
        self.assertEqual(env, {})


if __name__ == '__main__':
    unittest.main()
