import SwiftUI
import Core

/// One row of the checklist card (his `QuickSetupView` row): a 24 pt symbol, or a check once
/// done; title and detail; chevron. Pushes the row's page; a row waiting for the one before is
/// dimmed and doesn't open.
struct ClearSetupItem: View {
    let row: ClearSetupRow
    let list: SetupChecklist
    let open: () -> Void

    var body: some View {
        let done = list.isDone(row)
        let blocked = list.isBlocked(row)
        Button(action:open) {
            HStack(spacing:14) {
                Image(systemName:done ? "checkmark.circle.fill" : Self.symbol(row))
                    .font(.title3).foregroundStyle(Theme.accentText)
                    .frame(width:24)
                    .accessibilityHidden(true)
                VStack(alignment:.leading, spacing:6) {
                    Text(SetupChecklist.title(row)).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(list.detail(row)).font(.caption).foregroundStyle(Theme.ink2).monospacedDigit()
                        .fixedSize(horizontal:false, vertical:true)
                }
                Spacer(minLength:4)
                Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ink3)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(minHeight:76)
            .contentShape(Rectangle())
            .opacity(blocked ? 0.5 : 1)
        }
        .buttonStyle(RowPressStyle())
        .disabled(blocked)
        .accessibilityElement(children:.combine)
        .accessibilityValue(done ? "已完成" : "")
        .accessibilityIdentifier("setupRow-\(row)")
    }

    static func symbol(_ row: ClearSetupRow) -> String {
        switch row {
        case .account: "person.crop.circle"
        case .dorm: "house"
        case .laundry: "washer"
        case .controller: "drop"
        }
    }
}
