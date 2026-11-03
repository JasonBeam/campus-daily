import SwiftUI
import Core

/// 3.2: one program as its own card — selection mark, name, minutes, price. Selected: accent
/// tint and outline.
struct ClearLaundryProgramRow: View {
    let program: WasherProgram
    let selected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action:action) {
            HStack(alignment:typeSize.isAccessibilitySize ? .top : .center, spacing:14) {
                Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accentText : Theme.ink3)
                if typeSize.isAccessibilitySize {
                    VStack(alignment:.leading, spacing:6) { titles; price }
                    Spacer(minLength:0)
                } else {
                    titles
                    Spacer(minLength:8)
                    price
                }
            }
            .padding(18)
            .frame(maxWidth:.infinity, minHeight:82, alignment:.leading)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius:16, style:.continuous))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(program.workModelName)，\(program.time) 分钟，\(LaundryFormat.spokenYuan(program.price.yuan))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private var titles: some View {
        VStack(alignment:.leading, spacing:6) {
            Text(program.workModelName).font(.headline).foregroundStyle(Theme.ink)
            Text("\(program.time) 分钟").font(.subheadline).monospacedDigit().foregroundStyle(Theme.ink2)
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.ink2)
            }
        }
        .fixedSize(horizontal:false, vertical:true)
    }

    private var price: some View {
        Text(Theme.yuan(program.price.yuan))
            .font(.title3.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Theme.ink).lineLimit(1)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius:16, style:.continuous)
        return shape.fill(Theme.group)
            .overlay { if selected { shape.fill(Theme.accent.opacity(0.08)) } }
            .overlay { if selected { shape.strokeBorder(Theme.accent.opacity(0.5), lineWidth:1) } }
    }

    /// Note for the spin-only program (as 暖橙's `LaundryProgramRow`).
    private var note: String? { program.workModelName == "单脱水" ? "最多 3/4 桶，适合手洗的衣服甩干" : nil }
}
