//
//  ClearShowerCostRow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI

/// One row of the 本次费用 card: label on the left, value on the right; stacked under the label
/// at accessibility text sizes (`ClearAmountRow`).
struct ClearShowerCostRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        ClearAmountRow {
            Text(label).foregroundStyle(.secondary)
        } amount: {
            value
        }
        .accessibilityElement(children:.combine)
    }
}
