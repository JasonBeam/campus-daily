import SwiftUI

/// The 「学校洗衣机」 switch of the settings page: the live model's value and lock, or the DEBUG
/// demo's, where it flips locally (`previewOn`, seeded from the demo data).
@MainActor struct SchoolLaundrySwitch {
    let laundry: LaundryModel
    /// DEBUG demo data; nil = live model.
    let preview: HomeData?
    let previewOn: Binding<Bool?>

    var isOn: Bool { preview != nil ? (previewOn.wrappedValue ?? preview?.laundryEnabled ?? true) : laundry.schoolEnabled }
    var locked: Bool { preview?.laundryLocked ?? laundry.schoolSwitchLocked }
    var binding: Binding<Bool> {
        Binding(get:{ isOn }, set:{ on in
            // Default List insert/delete animation for 「常用洗衣机」 and 「洗衣洗好时」.
            withAnimation {
                if preview != nil { previewOn.wrappedValue = on } else { laundry.setSchoolEnabled(on) }
            }
        })
    }
}
