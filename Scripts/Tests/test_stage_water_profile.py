import importlib.util
import json
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location('stage_water_profile', Path(__file__).resolve().parents[1] / 'stage-water-profile.py')
_module = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_module)
validate_profile = _module.validate_profile


class PlatformBuildProfileTests(unittest.TestCase):
    def seed(self):
        return dict(secret='fixture-secret', sid='fixture-provider', bleName='fixture-ble', typeID=1, version=1)

    def validate(self, value):
        return validate_profile(json.dumps(value).encode())

    def test_platform_only_round_trip(self):
        self.assertEqual(self.validate(self.seed()), self.seed())

    def test_personal_or_device_fields_are_refused(self):
        for field in ('student_id', 'studentID', 'acc_token', 'custid', 'machineID', 'room', 'address', 'access'):
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.validate(dict(self.seed(), **{field: 'private-placeholder'}))

    def test_missing_fields_and_wrong_protocol_types_are_refused(self):
        for key in self.seed():
            value = self.seed(); del value[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(value)
        for key, value in [('typeID', True), ('typeID', -1), ('version', 0), ('version', '1'), ('version', 2147483648)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.validate(dict(self.seed(), **{key: value}))

    def test_header_controls_and_oversized_payloads_are_refused(self):
        for key in ('secret', 'sid', 'bleName'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(dict(self.seed(), **{key: 'bad\r\nfield'}))
        with self.assertRaises(ValueError):
            validate_profile(b' ' * 8193)

    def test_format_characters_are_refused_as_the_app_refuses_them(self):
        # The app's parser refuses Unicode control and format characters (Cc, Cf), such as a
        # zero-width space: a profile the build stages must not be refused at runtime.
        for text in ('fixture\u200bsid', 'fixture\u00adsid', 'fixture\ufeffsid', 'fixture\u0085sid'):
            with self.subTest(text=ascii(text)), self.assertRaises(ValueError):
                self.validate(dict(self.seed(), sid=text))
        self.validate(dict(self.seed(), sid='fixture-sid=1 ~/+'))


if __name__ == '__main__':
    unittest.main()
