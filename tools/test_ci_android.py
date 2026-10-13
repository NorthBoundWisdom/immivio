"""Offline checks for CI template caching and optional signing configuration."""
import base64
import contextlib
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import ci_android as ci


class CiBoundaries(unittest.TestCase):
    def check_build_mode(self, product="Immivio", receipt_product=None, build_type='Debug', receipt_type=None, environment=None, requested_type=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def build(args, env, sdk, **kwargs):
                artifacts = root/'artifacts';artifacts.mkdir(exist_ok=True)
                data = dict(apk=f'Immivio-QUEST-v1-{build_type.lower()}-test.apk', sha256='fixture', vendor='Quest',
                            product=product if receipt_product is None else receipt_product, build_type=build_type if receipt_type is None else receipt_type)
                (artifacts/f'Immivio-QUEST-v1-{build_type.lower()}-test.build.json').write_text(json.dumps(data))
            with patch.object(ci.player, 'ROOT', root), patch.object(ci.player, 'CACHE', root/'.cache'), \
                 patch.object(ci.player, 'LOGS', root/'logs'), \
                 patch.object(ci.player, 'build_lock', side_effect=contextlib.nullcontext), \
                 patch.object(ci.player, 'environment', return_value=({}, root/'sdk')), \
                 patch.object(ci.player, 'gradle_executable', return_value=root/'gradle'), \
                 patch.object(ci, 'check_export_path'), patch.object(ci.player, 'prepare_dependencies') as prepare, \
                 patch.object(ci.player, 'build', side_effect=build), patch.dict(ci.os.environ, environment or {}, clear=True):
                ci.build('Quest', 'godot', root/'templates', build_type=requested_type or build_type)
                self.assertEqual(prepare.call_args.args[1].build_type, build_type)
                summary = json.loads((root/'artifacts/ci-summary.json').read_text())
                self.assertEqual(summary[0]['product'], product)

    def test_job_selects_immivio_receipts(self):
        self.check_build_mode()

    def test_job_rejects_another_product_receipt(self):
        with self.assertRaisesRegex(RuntimeError, 'product differs'):
            self.check_build_mode(receipt_product='Other')

    def test_tag_ref_forces_release_even_when_debug_is_requested(self):
        self.assertEqual(ci.build_type_for_ref('Debug', {'GITHUB_REF': 'refs/tags/v0.6.0-fork.1'}), 'Release')
        self.check_build_mode(build_type='Release', environment={'GITHUB_REF': 'refs/tags/v0.6.0-fork.1'}, requested_type='Debug')
        self.check_build_mode(build_type='Release', environment={'GITHUB_REF': 'refs/tags/v0.6.0-fork.1'})

    def test_branch_and_pr_default_to_debug(self):
        for ref in ('refs/heads/main', 'refs/pull/1/merge'):
            self.assertEqual(ci.build_type_for_ref(environment={'GITHUB_REF': ref}), 'Debug')

    def test_manual_release_and_invalid_build_type(self):
        self.assertEqual(ci.build_type_for_ref('Release', {}), 'Release')
        self.assertEqual(ci.build_type_for_ref(environment={'CI_BUILD_TYPE': 'Release'}), 'Release')
        with self.assertRaisesRegex(ValueError, 'Debug or Release'):
            ci.build_type_for_ref('Invalid', {})

    def test_debug_jobs_do_not_decode_repository_signing_material(self):
        self.check_build_mode(environment={'CI_ANDROID_KEY_ALIAS': 'unused-in-debug'})

    def test_debug_receipt_cannot_pass_a_release_job(self):
        with self.assertRaisesRegex(RuntimeError, 'receipt type differs'):
            self.check_build_mode(build_type='Release', receipt_type='Debug')

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
