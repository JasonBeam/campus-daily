import SwiftUI
import Core

/// The 「学校洗衣机」 footnote, under the group that holds the switch.
struct SchoolLaundryFooter: View {
    let laundrySwitch: SchoolLaundrySwitch

    var body: some View {
        Text(SchoolLaundryPreference.footer(isOn:laundrySwitch.isOn, locked:laundrySwitch.locked))
            .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
    }
}
