import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'privacy-check.sh'

# Identifier-shaped values are put together at run time, so this file itself scans clean.
PHONE = '139' + '12345678'
MAC = ':'.join(['3c', '5a', 'b4', '01', '02', '03'])
CIPHERTEXT = 'AbCd' + 'x9' * 10 + '%3N'
OLD_SYNTHETIC_CIPHERTEXT = 'TESTsyscus%3Ntid' + '0' * 26 + '%1H00%7J'
VOUCHER = '2026' + '10300017'


class PrivacyCheckTests(unittest.TestCase):
    """privacy-check.sh on a scratch repository: what it flags in the staged files, and that it
    prints locations, never the values."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        self.write('README.md', 'synthetic only\n')

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        (self.repo / name).write_text(text)
        subprocess.run(['git', '-C', str(self.repo), 'add', name], check=True)

    def check(self, *extra, env=None):
        # Never the caller's own lists: no value list, no marker patterns unless a test sets them.
        base = {k: v for k, v in os.environ.items() if k not in ('LEAKCHECK_FILE', 'MARKER_PATTERNS')}
        return subprocess.run(['sh', str(SCRIPT), *extra, str(self.repo)], capture_output=True, text=True,
                              env=dict(base, **(env or {})))

    def assertFlagged(self, text, label):
        self.write('fixture.json', text)
        result = self.check('--allow-missing')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(label, result.stdout)
        self.assertIn('fixture.json:', result.stdout)
        return result

    def test_synthetic_values_pass(self):
        self.write('fixture.json', '{"phone": "13800000000", "custid": "TESTcustid0000000000000000000000000000001%",'
                                   ' "syscustid": "TESTsyscustid0000000000000000000000000001%25",'
                                   ' "voucherno": "99000991", "mac": "02:00:00:00:00:01"}\n')
        result = self.check('--allow-missing')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('0 suspicious', result.stdout)

    def test_a_phone_number_is_flagged_by_location_only(self):
        result = self.assertFlagged('{"phone": "%s"}\n' % PHONE, 'phone-like')
        self.assertNotIn(PHONE, result.stdout + result.stderr)

    def test_a_mac_address_is_flagged(self):
        self.assertFlagged('{"mac": "%s"}\n' % MAC, 'MAC')

    def test_a_custid_ciphertext_is_flagged(self):
        self.assertFlagged('{"custid": "%s"}\n' % CIPHERTEXT, 'custid ciphertext')

    def test_a_custid_that_keeps_a_real_tail_is_flagged(self):
        self.assertFlagged('{"syscustid": "%s"}\n' % OLD_SYNTHETIC_CIPHERTEXT, 'custid ciphertext')

    def test_a_card_voucher_is_flagged(self):
        self.assertFlagged('{"voucherno": "%s"}\n' % VOUCHER, 'card record voucher')

    def test_a_value_from_the_private_list_is_flagged(self):
        values = Path(self.tmp.name + '-values.txt')
        self.addCleanup(values.unlink)
        values.write_text('Synthetic-Private-Room\n')
        self.write('notes.md', 'lives in synthetic-private-room\n')
        result = self.check('--allow-missing', env=dict(LEAKCHECK_FILE=str(values)))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('notes.md:1', result.stdout)
        self.assertNotIn('synthetic-private-room', result.stdout.lower())

    def test_a_missing_value_list_fails_without_allow_missing(self):
        result = self.check()
        self.assertEqual(result.returncode, 2)

    def test_missing_lists_are_printed_as_skipped_with_allow_missing(self):
        result = self.check('--allow-missing')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('skipped: value scan', result.stdout)
        self.assertIn('skipped: marker scan', result.stdout)

    def test_a_value_list_set_to_a_missing_file_fails_even_with_allow_missing(self):
        absent = str(Path(self.tmp.name) / 'absent.txt')
        for extra in ((), ('--allow-missing',)):
            result = self.check(*extra, env=dict(LEAKCHECK_FILE=absent))
            self.assertEqual(result.returncode, 2, extra)
            self.assertIn('LEAKCHECK_FILE', result.stderr)
            self.assertNotIn('skipped', result.stdout)

    def test_marker_patterns_set_to_a_missing_file_fails_even_with_allow_missing(self):
        absent = str(Path(self.tmp.name) / 'absent-patterns.txt')
        for extra in ((), ('--allow-missing',)):
            result = self.check(*extra, env=dict(MARKER_PATTERNS=absent))
            self.assertEqual(result.returncode, 2, extra)
            self.assertIn('MARKER_PATTERNS', result.stderr)


if __name__ == '__main__':
    unittest.main()
