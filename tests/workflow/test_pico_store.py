"""Check compiled-manifest store rules against synthetic APKs, not preset strings."""
import copy
import hashlib
import json
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

from configs import pico_store, player_build as builder
from configs.android_manifest import ANDROID as A


class PicoStore(unittest.TestCase):
    certificate = "a" * 64

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / "fixture.apk"
        self.write_apk()
        self.manifest = ET.fromstring('''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
            package="com.northboundwisdom.immivio" android:versionCode="20" android:versionName="0.9.6" android:compileSdkVersion="36">
            <uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/>
            <application android:debuggable="false">
                <meta-data android:name="pvr.sdk.version" android:value="OpenXR"/>
                <meta-data android:name="pxr.sdk.version_code" android:value="5800"/>
                <activity android:name="Launcher" android:exported="true"><intent-filter>
                    <action android:name="android.intent.action.MAIN"/>
                    <category android:name="android.intent.category.LAUNCHER"/>
                    <category android:name="org.khronos.openxr.intent.category.IMMERSIVE_HMD"/>
                </intent-filter></activity>
            </application>
        </manifest>''')

    def write_apk(self, features=b"pico,immivio_appstore", abi="arm64-v8a"):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            for name, value in [('AndroidManifest.xml',b'compiled'), ('classes.dex',b'fixture'),
                                ('assets/project.binary',features), (f'lib/{abi}/libfixture.so',b'ELF')]:
                archive.writestr(name,value)

    def validate(self, **kwargs):
        return pico_store.validate(self.apk, self.manifest, certificate=self.certificate,
            expected_certificate=self.certificate, version='0.9.6', version_code=20, **kwargs)

    def test_actual_openxr_metadata_and_legacy_device_support_are_reported(self):
        report = self.validate()
        self.assertEqual(report['min_sdk'],29)
        self.assertEqual(report['pxr.sdk.version_code'],'5800')  # No invented Unity/Unreal 6.x SDK value.
        self.assertEqual(report['md5'],hashlib.md5(self.apk.read_bytes()).hexdigest())
        self.assertFalse(report['uploaded_baseline_checked'])
        self.assertIsNone(report['pvr.app.id'])

    def test_debug_testonly_and_diagnostic_entries_are_rejected(self):
        application = self.manifest.find('application')
        for flag in ['debuggable','testOnly']:
            application.set(A+flag,'true')
            with self.assertRaisesRegex(ValueError,'Debug/testOnly'):self.validate()
            application.set(A+flag,'false')
        receiver = ET.SubElement(application,'receiver',{A+'name':'org.vrpassthroughplayer.plugin.DebugDiagnosticsReceiver'})
        with self.assertRaisesRegex(ValueError,'diagnostic'):self.validate()
        application.remove(receiver)

    def test_non_store_payload_and_other_abis_are_rejected(self):
        for features,abi,message in [(b'immivio_web','arm64-v8a','appstore'),
                                     (b'immivio_appstore,immivio_web','arm64-v8a','appstore'),
                                     (b'immivio_appstore','armeabi-v7a','ARM64')]:
            with self.subTest(features=features,abi=abi):
                self.write_apk(features,abi)
                with self.assertRaisesRegex(ValueError,message):self.validate()

    def test_sdk_package_version_and_multiple_launchers_cannot_drift(self):
        for target,key,value in [(self.manifest,'package','com.other.app'),
                                 (self.manifest,A+'versionCode','19'),
                                 (self.manifest,A+'versionName','other'),
                                 (self.manifest.find('uses-sdk'),A+'minSdkVersion','30'),
                                 (self.manifest.find('uses-sdk'),A+'targetSdkVersion','22')]:
            original=target.get(key);target.set(key,value)
            with self.assertRaises(ValueError):self.validate()
            target.set(key,original)
        application=self.manifest.find('application')
        application.append(copy.deepcopy(application.find('activity')))
        with self.assertRaisesRegex(ValueError,'exactly one launcher'):self.validate()

    def test_missing_sdk_and_wrong_optional_app_id_are_rejected(self):
        application=self.manifest.find('application')
        for item in list(application.findall('meta-data')):application.remove(item)
        with self.assertRaisesRegex(ValueError,'SDK version'):self.validate()
        ET.SubElement(application,'meta-data',{A+'name':'pxr.sdk.version_code',A+'value':'5800'})
        ET.SubElement(application,'meta-data',{A+'name':'pvr.app.id',A+'value':'12345'})
        with self.assertRaisesRegex(ValueError,'pvr.app.id'):self.validate()
        self.assertEqual(self.validate(expected_app_id='12345')['pvr.app.id'],'12345')

    def test_uploaded_track_baseline_enforces_signature_version_and_duplicate_rules(self):
        baseline={'package_name':pico_store.PACKAGE,'certificate_sha256':self.certificate,
                  'version_code':20,'md5':'b'*32}
        self.assertTrue(self.validate(baseline=baseline)['uploaded_baseline_checked'])
        for key,value,message in [('package_name','other','package/signature'),
                                  ('certificate_sha256','c'*64,'package/signature'),
                                  ('version_code',21,'versionCode'),
                                  ('md5',hashlib.md5(self.apk.read_bytes()).hexdigest(),'duplicate')]:
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError,message):self.validate(baseline={**baseline,key:value})
        with self.assertRaisesRegex(ValueError,'incomplete'):self.validate(baseline={})

    def test_size_and_signer_mismatch_are_rejected(self):
        with patch.object(pico_store,'MAX_APK_BYTES',1):
            with self.assertRaisesRegex(ValueError,'4 GB'):self.validate()
        with self.assertRaisesRegex(ValueError,'signer'):
            pico_store.validate(self.apk,self.manifest,certificate='c'*64,
                expected_certificate=self.certificate,version='0.9.6',version_code=20)

    def test_persistent_key_survives_disposable_artifact_cleanup(self):
        root=Path(self.directory.name)
        persistent=root/'private-config/signing';persistent.mkdir(parents=True)
        key=persistent/'immivio-release.keystore';key.write_bytes(b'fixed project key')
        (persistent/'immivio-signing.json').write_text(json.dumps({'keystore':str(key),'alias':'immivio','password':'fixture'}))
        artifacts=root/'artifacts';artifacts.mkdir();(artifacts/'unrelated.bin').write_bytes(b'disposable')
        shutil.rmtree(artifacts)
        with patch.object(builder,'ROOT',root),patch.object(builder,'run') as run:
            env=builder.signing_environment({'IMMIVIO_SIGNING_DIR':str(persistent)},require_existing=True)
            self.assertEqual(env['GODOT_ANDROID_KEYSTORE_RELEASE_PATH'],str(key))
            self.assertEqual(key.read_bytes(),b'fixed project key')
            run.assert_not_called()

    def test_legacy_migration_cannot_overwrite_a_different_persistent_key(self):
        root=Path(self.directory.name)
        legacy=root/'artifacts/signing';legacy.mkdir(parents=True)
        source=legacy/'immivio-release.keystore';source.write_bytes(b'legacy key')
        (legacy/'immivio-signing.json').write_text(json.dumps({'keystore':str(source),'alias':'immivio','password':'fixture'}))
        target=root/'private-config/signing';target.mkdir(parents=True)
        existing=target/'immivio-release.keystore';existing.write_bytes(b'different key')
        with patch.object(builder,'ROOT',root):
            with self.assertRaisesRegex(RuntimeError,'refusing to overwrite'):
                builder.signing_environment({'IMMIVIO_SIGNING_DIR':str(target)},require_existing=True)
        self.assertEqual(existing.read_bytes(),b'different key')

    def test_store_releases_never_generate_an_ephemeral_key(self):
        with patch.object(builder,'ROOT',Path(self.directory.name)),patch.object(builder,'run') as run:
            with self.assertRaisesRegex(RuntimeError,'existing project release key'):
                builder.signing_environment({"IMMIVIO_SIGNING_DIR":str(Path(self.directory.name)/"persistent")},require_existing=True)
            run.assert_not_called()


if __name__ == '__main__':unittest.main()
