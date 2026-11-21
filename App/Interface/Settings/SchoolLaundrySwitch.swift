//
//  SchoolLaundrySwitch.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Core

/// The 「学校洗衣机」 switch of the settings page: the live model's value and lock, or the DEBUG
/// demo's, where it flips locally (`previewOn`, seeded from the demo data).
@MainActor struct SchoolLaundrySwitch {
    let laundry: LaundryModel
    /// DEBUG demo data; nil = live model.
    let preview: HomeData?
    let previewOn: Binding<Bool?>
    /// In the sample the switch keeps its value and says `SampleCopy.blocked`.
    var sample: SampleMode? = nil

    var isOn: Bool { preview != nil ? (previewOn.wrappedValue ?? preview?.laundryEnabled ?? true) : laundry.schoolEnabled }
    var locked: Bool { preview?.laundryLocked ?? laundry.schoolSwitchLocked }
    var binding: Binding<Bool> {
        Binding(get:{ isOn }, set:{ on in
            if let sample, sample.isActive { sample.perform(.bindWasher) {}; return }
            // Default List insert/delete animation for 「常用洗衣机」 and 「洗衣洗好时」.
            withAnimation {
                if preview != nil { previewOn.wrappedValue = on } else { laundry.setSchoolEnabled(on) }
            }
        })
    }
}
