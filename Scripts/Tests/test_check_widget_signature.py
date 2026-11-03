import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location('check_widget_signature', Path(__file__).resolve().parents[1] / 'check-widget-signature.py')
_module = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_module)
keychain_problem = _module.keychain_problem
app_group_problem = _module.app_group_problem

APP_PRIVATE = 'TEAM000099.com.beamjason.xiaorichang'
SHARED = 'TEAM000099.com.beamjason.xiaorichang.shared'


class KeychainGroupRuleTests(unittest.TestCase):
    def test_signed_build_as_listed_in_the_entitlements_passes(self):
        self.assertIsNone(keychain_problem([APP_PRIVATE, SHARED], [SHARED]))

    def test_private_group_in_the_widget_is_refused(self):
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, SHARED], [SHARED, APP_PRIVATE]))
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, SHARED], [APP_PRIVATE]))

    def test_shared_group_first_in_the_app_is_refused(self):
        self.assertIsNotNone(keychain_problem([SHARED, APP_PRIVATE], [SHARED]))

    def test_names_must_match_exactly(self):
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, SHARED], ['TEAM000099.other.com.beamjason.xiaorichang.shared']))
        self.assertIsNotNone(keychain_problem(['TEAM000099.x.com.beamjason.xiaorichang', SHARED], [SHARED]))

    def test_team_prefixes_must_match(self):
        other = 'TEAM000098.com.beamjason.xiaorichang.shared'
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, other], [other]))

    def test_app_must_list_the_shared_group(self):
        self.assertIsNotNone(keychain_problem([APP_PRIVATE], [SHARED]))

    def test_groups_follow_the_builds_keychain_group(self):
        own, own_shared = 'TEAM000099.org.example.daily', 'TEAM000099.org.example.daily.shared'
        self.assertIsNone(keychain_problem([own, own_shared], [own_shared], 'org.example.daily'))
        self.assertIsNotNone(keychain_problem([own, own_shared], [own_shared]))
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, SHARED], [SHARED], 'org.example.daily'))

    def test_wildcards_and_empty_lists_are_refused(self):
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, 'TEAM000099.*'], [SHARED]))
        self.assertIsNotNone(keychain_problem([], [SHARED]))
        self.assertIsNotNone(keychain_problem([APP_PRIVATE, SHARED], []))


GROUP = 'group.com.beamjason.xiaorichang'


class AppGroupRuleTests(unittest.TestCase):
    def test_both_entitled_to_the_group_named_in_info_plist_passes(self):
        self.assertIsNone(app_group_problem([GROUP], [GROUP], GROUP, GROUP))

    def test_a_signing_that_drops_the_group_is_refused(self):
        self.assertIsNotNone(app_group_problem([], [GROUP], GROUP, GROUP))
        self.assertIsNotNone(app_group_problem([GROUP], [], GROUP, GROUP))

    def test_a_group_renamed_by_the_signer_is_refused(self):
        other = 'group.org.example.daily'
        self.assertIsNotNone(app_group_problem([other], [other], GROUP, GROUP))
        self.assertIsNotNone(app_group_problem([GROUP], [other], GROUP, GROUP))

    def test_the_widget_must_name_the_apps_group(self):
        widget_own = GROUP + '.balances'
        self.assertIsNotNone(app_group_problem([GROUP], [GROUP, widget_own], GROUP, widget_own))

    def test_info_plist_must_name_a_group(self):
        self.assertIsNotNone(app_group_problem([GROUP], [GROUP], None, GROUP))
        self.assertIsNotNone(app_group_problem([GROUP], [GROUP], GROUP, ''))

    def test_groups_follow_the_builds_group(self):
        own = 'group.org.example.daily'
        self.assertIsNone(app_group_problem([own], [own], own, own))
        self.assertIsNone(app_group_problem([own, GROUP], [own], own, own), 'other groups may be listed too')


if __name__ == '__main__':
    unittest.main()
