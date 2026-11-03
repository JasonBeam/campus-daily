import SwiftUI
import Core

/// 3.2 / 3.3: 「选程序」 and the machine's programs. Not selectable while the machine is busy or
/// unavailable (dimmed), nor while an order is being placed.
struct ClearLaundryProgramList: View {
    let programs: [WasherProgram]
    /// The selected program's id; nil when nothing can be selected.
    let selectedID: Int?
    let enabled: Bool
    let dimmed: Bool
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment:.leading, spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Text("选程序").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength:8)
                Text("U净 当前价格").font(.caption).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal,4)
            ForEach(programs, id:\.id) { program in
                ClearLaundryProgramRow(program:program, selected:selectedID == program.id) { select(program.id) }
                    .disabled(!enabled)
                    .opacity(dimmed ? 0.4 : 1)
            }
        }
    }
}
