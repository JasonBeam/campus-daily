import SwiftUI
import Core

/// 「选择程序」 and the machine's programs. Not selectable while an order is being placed (dimmed).
struct ClearLaundryProgramList: View {
    let programs: [WasherProgram]
    /// The selected program's id; nil when nothing can be selected.
    let selectedID: Int?
    let enabled: Bool
    let dimmed: Bool
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment:.leading, spacing:20) {
            HStack(alignment:.firstTextBaseline) {
                Text(ClearLaundryCopy.programsTitle).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength:8)
                Text(ClearLaundryCopy.programsNote).font(.caption).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal,4)
            VStack(spacing:10) {
                ForEach(programs, id:\.id) { program in
                    ClearLaundryProgramRow(program:program, selected:selectedID == program.id) { select(program.id) }
                        .disabled(!enabled)
                        .opacity(dimmed ? 0.4 : 1)
                }
            }
        }
    }
}
