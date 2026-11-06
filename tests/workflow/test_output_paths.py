"""Output organization must preserve data and keep packages/keys out of cleanup."""
from contextlib import redirect_stdout
import io
import os
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configs import output_paths as outputs, ci_support as ci, player_build as player


class OutputLayout(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def file(self, name, data=b"fixture"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def package(self, directory="artifacts", name="Immivio-PICO-0.9.6-appstore-release-20261106.apk"):
        apk = self.file(directory+'/'+name,b'original APK bytes')
        record={"apk":name,"vendor":"Pico","channel":"appstore","build_type":"Release","sha256":"a"*64}
        receipt=apk.with_suffix('.build.json');receipt.write_text(json.dumps(record))
        report=apk.with_suffix('.store-report.json');report.write_bytes(b'original store report')
        return apk,receipt,report

    def organize(self, **kwargs):
        with redirect_stdout(io.StringIO()):return outputs.organize(self.root,**kwargs)

    def test_grouped_package_moves_preserve_all_companion_bytes(self):
        files=self.package();before={p.name:p.read_bytes() for p in files}
        self.file('artifacts/logs/old.log');self.file('artifacts/manual.log')
        self.file('artifacts/native-inspection/old/libmpv.so')
        self.file('build/dependency_seed_repos/source.txt')
        self.file('build/android.properties')
        self.organize(dry_run=True)
        self.assertTrue(files[0].exists())
        self.assertFalse((self.root/'artifacts/packages').exists())
        self.organize()
        folder=outputs.packages(self.root,'Pico','appstore','Release')
        self.assertEqual({p.name:p.read_bytes() for p in folder.iterdir()},before)
        self.assertTrue((self.root/'build/intermediates/legacy-apk-inspection/old/libmpv.so').is_file())
        self.assertTrue((self.root/'artifacts/archive/legacy-build/dependency_seed_repos/source.txt').is_file())
        self.assertTrue((self.root/'artifacts/logs/build/previous-layout/old.log').is_file())
        self.assertTrue((self.root/'artifacts/logs/manual/manual.log').is_file())
        self.assertEqual(self.organize(),[])
        reports=list((self.root/'artifacts/reports/organization').glob('*.json'))
        self.assertTrue(any(json.loads(p.read_text())['moves'] for p in reports))

    def test_collision_cannot_overwrite_canonical_package_or_break_pairing(self):
        old=self.package()
        folder=outputs.packages(self.root,'Pico','appstore','Release')
        self.file(str(folder.relative_to(self.root)/old[0].name),b'canonical new APK')
        self.organize()
        self.assertEqual((folder/old[0].name).read_bytes(),b'canonical new APK')
        archived=self.root/'artifacts/archive/legacy-packages'/old[0].stem
        self.assertEqual((archived/old[0].name).read_bytes(),b'original APK bytes')
        self.assertEqual(json.loads((archived/old[1].name).read_text())['apk'],old[0].name)

    def test_clean_scopes_preserve_deliverables_cache_and_external_key(self):
        apk,_,_=self.package('artifacts/packages/PICO/appstore/release')
        self.file('.cache/verified/marker')
        secret=self.file('private-config/immivio/signing/immivio-release.keystore')
        self.file('build/intermediates/temporary.so')
        self.file('build/tests/godot/temporary.cfg')
        self.file('artifacts/logs/build/latest.log')
        self.file('artifacts/tests/godot/junit.xml')
        self.file('artifacts/captures/ui/frame.png')
        for scope in ('build','logs','tests','captures'):
            with redirect_stdout(io.StringIO()):outputs.clean(self.root,scope)
        self.assertTrue(apk.exists());self.assertTrue(secret.exists())
        self.assertTrue((self.root/'.cache/verified/marker').exists())
        with self.assertRaises(ValueError):outputs.clean(self.root,'packages')

    def test_intermediate_cleanup_preserves_configuration_and_package(self):
        state=self.file('build/android/state/Pico-Release.json')
        self.file('build/intermediates/apk-inspection/libmpv.so')
        with redirect_stdout(io.StringIO()):outputs.clean(self.root,'intermediates')
        self.assertTrue(state.exists())
        self.assertFalse((self.root/'build/intermediates').exists())

    def test_signing_material_blocks_cleanup_and_archival(self):
        key=self.file('build/accidental/immivio-release.keystore')
        with self.assertRaisesRegex(RuntimeError,'Signing material'):outputs.clean(self.root)
        self.assertTrue(key.exists())
        with self.assertRaisesRegex(RuntimeError,'Signing material'):self.organize()
        self.assertTrue(key.exists())

    def test_symlinked_output_cannot_clean_or_move_outside_workspace(self):
        outside=self.root/'private-config';outside.mkdir()
        key=self.file('private-config/keep.txt')
        try:(self.root/'build').symlink_to(outside,target_is_directory=True)
        except OSError:self.skipTest('Symlink creation unavailable')
        with self.assertRaisesRegex(RuntimeError,'symlinked'):outputs.clean(self.root)
        self.assertTrue(key.exists())

    def test_latest_receipt_ignores_archived_or_missing_apks_and_summaries_use_nested_paths(self):
        folder=outputs.packages(self.root,'Pico','appstore','Release')
        apk,receipt,_=self.package(str(folder.relative_to(self.root)))
        self.package('artifacts/archive/old')
        with patch.object(player,'ROOT',self.root),patch.dict('os.environ',{'GITHUB_REF':'refs/heads/main'}):
            self.assertEqual(ci.latest_receipt_file('Pico','Release'),receipt)
            ci.ci_package_metadata('Pico','Release')
            report=outputs.ci_reports(self.root,'appstore','Release')
            self.assertIn('packages/PICO/appstore/release/'+apk.name,(report/'SHA256SUMS.txt').read_text())
            apk.unlink()
            with self.assertRaisesRegex(RuntimeError,'No packaged APK'):ci.latest_receipt('Pico','Release')

    def test_canonical_profile_wins_over_a_newer_flat_legacy_copy(self):
        _,canonical,_=self.package('artifacts/packages/PICO/appstore/release')
        _,legacy,_=self.package()
        os.utime(legacy,(2_000_000_000,2_000_000_000))
        with patch.object(player,'ROOT',self.root):
            self.assertEqual(ci.latest_receipt_file('Pico','Release'),canonical)

    def test_apk_inspection_always_removes_expanded_native_libraries(self):
        for error in (False,True):
            visited=[]
            def inspect(_apk,_env,_sdk,directory):
                visited.append(directory);(directory/'libmpv.so').write_bytes(b'ELF')
                if error:raise RuntimeError('fixture failure')
                return 'hash'
            with patch.object(player,'ROOT',self.root),patch.object(player,'_inspect_package',side_effect=inspect):
                if error:
                    with self.assertRaisesRegex(RuntimeError,'fixture failure'):player.inspect_package(Path('fixture.apk'),{},Path('sdk'))
                else:self.assertEqual(player.inspect_package(Path('fixture.apk'),{},Path('sdk')),'hash')
            self.assertFalse(visited[0].exists())
