import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / '.githooks' / 'pre-commit'

# Stands in for swiftformat: records its arguments and puts the header it was given in
# front of each file the way the fileHeader rule does (`// ` before each line, `//` for an
# empty one), with a fixed date.
FAKE_SWIFTFORMAT = r'''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if args == ['--version']:
    print('0.0.0'); sys.exit(0)
with open(os.environ['FAKE_SWIFTFORMAT_LOG'], 'a') as log:
    log.write(' '.join(args) + '\n')
header = args[args.index('--header') + 1]
files = [a for a in args if a.endswith('.swift')]
for path in files:
    name = os.path.basename(path)
    text = header.replace('\\n', '\n').replace('{file}', name).replace('{created}', '2026/11/21')
    lines = ['// ' + line if line else '//' for line in text.split('\n')]
    with open(path) as fh:
        body = fh.read()
    with open(path, 'w') as fh:
        fh.write('\n'.join(lines) + '\n\n' + body)
'''


class PreCommitHookTests(unittest.TestCase):
    """.githooks/pre-commit on a scratch repository: new Swift files get a header signed with
    user.github; existing headers and modified files stay as they are."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / 'repo'
        self.bin = Path(self.tmp.name) / 'bin'
        self.log = Path(self.tmp.name) / 'swiftformat.log'
        self.bin.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        hooks = self.repo / '.githooks'
        hooks.mkdir()
        shutil.copy(HOOK, hooks / 'pre-commit')
        self.git('config', 'core.hooksPath', '.githooks')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        (self.repo / '.swiftformat').write_text('--rules fileHeader\n')
        self.git('add', '.')
        self.commit('init')

    def tearDown(self):
        self.tmp.cleanup()

    def install_swiftformat(self):
        fake = self.bin / 'swiftformat'
        fake.write_text(FAKE_SWIFTFORMAT)
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)

    def env(self):
        # Clean environment so tests never inherit host git/shell wrappers or a real swiftformat.
        return {
            'PATH': f'{self.bin}:/usr/bin:/bin',
            'HOME': self.tmp.name,
            'FAKE_SWIFTFORMAT_LOG': str(self.log),
            'PRE_COMMIT_KEEP_PATH': '1',
        }

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], check=True,
                              capture_output=True, text=True, env=self.env()).stdout

    def commit(self, message):
        return subprocess.run(['git', '-C', str(self.repo), 'commit', '-q', '-m', message],
                              capture_output=True, text=True, env=self.env())

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def committed(self, name):
        return self.git('show', f'HEAD:{name}')

    def test_new_file_gets_a_header_with_the_github_name(self):
        self.install_swiftformat()
        self.git('config', 'user.github', '@Someone')
        self.write('App/New View.swift', 'import SwiftUI\n')
        self.git('add', '.')
        result = self.commit('add view')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.committed('App/New View.swift'),
                         '//\n//  New View.swift\n//  XiaoRiChang\n//\n'
                         '//  Created by @Someone on 2026/11/21.\n//\n\nimport SwiftUI\n')
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_existing_header_and_modified_files_are_left_alone(self):
        self.install_swiftformat()
        self.git('config', 'user.github', 'Someone')
        old = 'struct Old {}\n'
        self.write('Old.swift', old)
        self.git('add', '.')
        self.commit('old file')  # added: gets a header
        self.write('Old.swift', 'struct Old {}\n')  # header removed by hand
        headed = '//\n//  Kept.swift\n//  XiaoRiChang\n//\n//  Created by @Other on 2025/01/02.\n//\n\nlet x = 1\n'
        self.write('Kept.swift', headed)
        self.write('Vendor/Lib.swift', 'let vendored = 1\n')
        self.log.unlink(missing_ok=True)
        self.git('add', '.')
        result = self.commit('modify and add headed file')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.committed('Old.swift'), old)
        self.assertEqual(self.committed('Kept.swift'), headed)
        self.assertEqual(self.committed('Vendor/Lib.swift'), 'let vendored = 1\n')
        self.assertFalse(self.log.exists())

    def test_missing_github_name_stops_the_commit(self):
        self.install_swiftformat()
        self.write('New.swift', 'let a = 1\n')
        self.git('add', '.')
        result = self.commit('add')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('git config user.github', result.stderr)
        self.assertNotIn('test@example.invalid', result.stderr)

    def test_missing_swiftformat_stops_the_commit(self):
        self.git('config', 'user.github', 'Someone')
        self.write('New.swift', 'let a = 1\n')
        self.git('add', '.')
        result = self.commit('add')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('swiftformat not found', result.stderr)

    def test_partly_staged_new_file_is_checked_not_changed(self):
        self.install_swiftformat()
        self.git('config', 'user.github', 'Someone')
        self.write('New.swift', 'let a = 1\n')
        self.git('add', '.')
        self.write('New.swift', 'let a = 1\nlet b = 2\n')
        result = self.commit('add')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('New.swift', result.stderr)
        self.assertEqual((self.repo / 'New.swift').read_text(), 'let a = 1\nlet b = 2\n')

    def test_commit_without_swift_files_needs_nothing(self):
        self.write('notes.txt', 'hi\n')
        self.git('add', '.')
        result = self.commit('notes')
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
