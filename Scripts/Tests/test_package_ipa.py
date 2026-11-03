import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'package-ipa.py'
PROFILE = dict(secret='synthetic-secret', sid='synthetic', bleName='SYNTHETIC', typeID=0, version=1)


class PackageIpaTests(unittest.TestCase):
    """package-ipa.py on a fake unsigned Release build (no Mach-O files, so no codesign call)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.app = root / 'Release-iphoneos' / 'XiaoRiChang.app'
        widget = self.app / 'PlugIns' / 'XiaoRiChangWidget.appex'
        widget.mkdir(parents=True)
        info = dict(CFBundleShortVersionString='9.9.9', CFBundleVersion='991')
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (widget / 'Info.plist').write_bytes(plistlib.dumps(info))
        (self.app / 'CampusWaterPlatform.json').write_text(json.dumps(PROFILE))
        self.profile = root / 'profile.json'
        self.profile.write_text(json.dumps(PROFILE))
        self.output = root / 'out'

    def tearDown(self):
        self.tmp.cleanup()

    def package(self, app=None):
        return subprocess.run([sys.executable, str(SCRIPT), '--app', str(app or self.app), '--output', str(self.output),
                               '--platform-profile', str(self.profile)], capture_output=True, text=True)

    def assertRefused(self, result, words):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(words, result.stderr)
        self.assertFalse(any(self.output.glob('*.ipa')), 'nothing is packaged')

    def test_a_clean_release_build_is_packaged_with_its_checksum(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)
        ipa = self.output / 'XiaoRiChang-9.9.9-build991-unsigned.ipa'
        with zipfile.ZipFile(ipa) as archive:
            self.assertIn('Payload/XiaoRiChang.app/PlugIns/XiaoRiChangWidget.appex/Info.plist', archive.namelist())
        self.assertTrue((self.output / (ipa.name + '.sha256')).read_text().endswith(ipa.name + '\n'))

    def test_only_a_release_iphoneos_app_is_taken(self):
        debug = Path(self.tmp.name) / 'Debug-iphoneos' / 'XiaoRiChang.app'
        debug.parent.mkdir()
        self.app.rename(debug)
        self.assertRefused(self.package(app=debug), 'Release-iphoneos')

    def test_a_bundled_profile_that_differs_from_the_supplied_one_is_refused(self):
        (self.app / 'CampusWaterPlatform.json').write_text(json.dumps(dict(PROFILE, sid='other')))
        self.assertRefused(self.package(), 'differs')

    def test_a_bundled_profile_with_personal_fields_is_refused(self):
        (self.app / 'CampusWaterPlatform.json').write_text(json.dumps(dict(PROFILE, room='991')))
        self.assertRefused(self.package(), 'platform-only resource')

    def test_a_build_without_the_widget_is_refused(self):
        for path in sorted((self.app / 'PlugIns').rglob('*'), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
        self.assertRefused(self.package(), 'extension missing')

    def test_private_files_and_signing_material_are_refused(self):
        for name in ['imported.waterconfig', 'WaterPlatformProfile.json', 'embedded.mobileprovision',
                     'key.p12', 'trace.har', 'ble.pklg', 'capture.pcapng']:
            with self.subTest(name=name):
                path = self.app / name
                path.write_text('synthetic')
                self.assertRefused(self.package(), 'refusing package')
                path.unlink()

    def test_an_existing_ipa_is_not_overwritten(self):
        self.assertEqual(self.package().returncode, 0)
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)


if __name__ == '__main__':
    unittest.main()
