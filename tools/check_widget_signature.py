#!/usr/bin/env python3
"""Check a SIGNED app's main/widget keychain capability before installation."""
import argparse
import plistlib
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--app', required=True, type=Path)
args = p.parse_args()
app = args.app.resolve()
widget = app / 'PlugIns/CampusDailyWidget.appex'
if not widget.is_dir():
    p.error('Widget extension is missing; signing must preserve app extensions')
def entitlements(bundle):
    r = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True)
    if r.returncode != 0 or not r.stdout.strip():
        p.error('A signed app and signed widget are required for this check')
    return plistlib.loads(r.stdout)
a, w = entitlements(app), entitlements(widget)
ag, wg = a.get('keychain-access-groups', []), w.get('keychain-access-groups', [])
if not ag or not wg or ag[0] != wg[0] or '*' in ag[0]:
    p.error('Main app and widget must have the same explicit first keychain access group')
for bundle in [app,widget]:
    if 'CampusKeychainGroup' in plistlib.loads((bundle/'Info.plist').read_bytes()):
        p.error('Stale build-time keychain group found in Info.plist')
print('Signed main app and widget share the same default keychain group.')
