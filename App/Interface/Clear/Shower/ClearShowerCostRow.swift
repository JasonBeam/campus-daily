import SwiftUI

/// One row of the 本次费用 card: label on the left, value on the right; stacked when they don't
/// fit side by side (large text).
struct ClearShowerCostRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack {
                Text(label).foregroundStyle(.secondary).fixedSize()
                Spacer()
                value.fixedSize()
            }
            VStack(alignment:.leading, spacing:6) {
                Text(label).foregroundStyle(.secondary)
                value
            }
            .frame(maxWidth:.infinity, alignment:.leading)
        }
        .accessibilityElement(children:.combine)
    }
}
