#!/usr/bin/env python3
"""Check a SIGNED app's main/widget keychain and App Group capabilities before installation."""
import argparse
import plistlib
import subprocess
from pathlib import Path

# The default APP_BUNDLE_IDENTIFIER; a build carries its own in Info.plist KeychainGroupIdentifier.
PRIVATE = 'com.beamjason.xiaorichang'


def keychain_problem(app_groups, widget_groups, private=PRIVATE):
    """The first rule the two keychain-access-groups lists break, or None.

    iOS writes an item without a group into the first listed group, so the order is part of
    the contract: the app lists <prefix>.PRIVATE first, the widget lists <prefix>.SHARED and
    nothing else, both under the same team prefix. SHARED is PRIVATE + '.shared'.
    """
    shared = private + '.shared'
    if any('*' in g for g in app_groups + widget_groups):
        return 'Keychain access groups must be explicit'
    if len(widget_groups) != 1:
        return 'The widget must list exactly one keychain group, the shared one'
    if not app_groups:
        return 'The main app lists no keychain group'
    prefix, dot, rest = app_groups[0].partition('.')
    if not prefix or not dot or rest != private:
        return 'The main app must list its private keychain group <prefix>.%s first' % private
    if widget_groups[0] != prefix + '.' + shared:
        return 'The widget group must be %s.%s (same team prefix as the app)' % (prefix, shared)
    if widget_groups[0] not in app_groups:
        return 'The main app must list the shared keychain group too'
    return None


def app_group_problem(app_groups, widget_groups, app_info_group, widget_info_group):
    """The first rule the App Group entitlements break, or None.

    Both Info.plists name the App Group the code opens (AppGroupIdentifier; the widget carries
    the app's). Both targets must be entitled to that group, or the lease and the shared files
    have no container and the widget never refreshes.
    """
    if not app_info_group or not widget_info_group:
        return 'Info.plist must name the App Group (AppGroupIdentifier) in the app and the widget'
    if widget_info_group != app_info_group:
        return 'The widget must name the app App Group %s in Info.plist' % app_info_group
    if app_info_group not in app_groups:
        return 'The main app is not entitled to the App Group %s named in Info.plist' % app_info_group
    if widget_info_group not in widget_groups:
        return 'The widget is not entitled to the App Group %s named in Info.plist' % widget_info_group
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
    private = plistlib.loads((app / 'Info.plist').read_bytes()).get('KeychainGroupIdentifier', PRIVATE)
    problem = keychain_problem(list(a.get('keychain-access-groups', [])), list(w.get('keychain-access-groups', [])), private)
    if problem:
        p.error(problem)
    app_info, widget_info = (plistlib.loads((b / 'Info.plist').read_bytes()) for b in (app, widget))
    problem = app_group_problem(list(a.get('com.apple.security.application-groups', [])),
                                list(w.get('com.apple.security.application-groups', [])),
                                app_info.get('AppGroupIdentifier'), widget_info.get('AppGroupIdentifier'))
    if problem:
        p.error(problem)
    print('Signed main app and widget share the keychain group and the App Group; app-only items stay in the app keychain group.')


if __name__ == '__main__':
    main()
