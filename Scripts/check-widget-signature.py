#!/usr/bin/env python3
"""Check a SIGNED app's main/widget keychain capability before installation."""
import argparse
import plistlib
import subprocess
from pathlib import Path

PRIVATE = 'com.beamjason.xiaorichang'
SHARED = 'com.beamjason.xiaorichang.shared'


def keychain_problem(app_groups, widget_groups):
    """The first rule the two keychain-access-groups lists break, or None.

    iOS writes an item without a group into the first listed group, so the order is part of
    the contract: the app lists <prefix>.PRIVATE first, the widget lists <prefix>.SHARED and
    nothing else, both under the same team prefix.
    """
    if any('*' in g for g in app_groups + widget_groups):
        return 'Keychain access groups must be explicit'
    if len(widget_groups) != 1:
        return 'The widget must list exactly one keychain group, the shared one'
    if not app_groups:
        return 'The main app lists no keychain group'
    prefix, dot, rest = app_groups[0].partition('.')
    if not prefix or not dot or rest != PRIVATE:
        return 'The main app must list its private keychain group <prefix>.%s first' % PRIVATE
    if widget_groups[0] != prefix + '.' + SHARED:
        return 'The widget group must be %s.%s (same team prefix as the app)' % (prefix, SHARED)
    if widget_groups[0] not in app_groups:
        return 'The main app must list the shared keychain group too'
    if app_groups[0] in widget_groups:
        return 'The widget must not list the app private keychain group'
    return None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', required=True, type=Path)
    args = p.parse_args()
    app = args.app.resolve()
    widget = app / 'PlugIns/XiaoRiChangWidget.appex'
    if not widget.is_dir():
        p.error('Widget extension is missing; signing must preserve app extensions')

    def entitlements(bundle):
        r = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True)
        if r.returncode != 0 or not r.stdout.strip():
            p.error('A signed app and signed widget are required for this check')
        return plistlib.loads(r.stdout)

    a, w = entitlements(app), entitlements(widget)
    problem = keychain_problem(list(a.get('keychain-access-groups', [])), list(w.get('keychain-access-groups', [])))
    if problem:
        p.error(problem)
    for bundle in [app, widget]:
        if 'CampusKeychainGroup' in plistlib.loads((bundle / 'Info.plist').read_bytes()):
            p.error('Stale build-time keychain group found in Info.plist')
    print('Signed main app and widget share the keychain group; app-only items stay in the app group.')


if __name__ == '__main__':
    main()
