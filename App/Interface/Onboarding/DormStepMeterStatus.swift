import SwiftUI
import Core

/// What the meter lookup shows under the dorm on the first-run dorm step (暖橙's guide and
/// 清爽's 宿舍 page): still looking, the apartment question (kept after a pick; a tap binds the
/// row), or the school too slow. Nothing for a match or a plain stop.
struct DormStepMeterStatus: View {
    /// The meter question last asked, kept once a row is bound so another pick binds that one
    /// instead; its lookup's person stamp; the row picked (bound at once).
    struct Asked: Equatable {
        var question: MeterQuestion?
        var stamp = -1
        var pick: String?
    }

    @Binding var asked: Asked
    /// The DEBUG demo's line (nil: the lookup's); when previewing nothing is bound.
    var preview: DormStepMeter?
    var previewing = false
    /// A row of an apartment that halted before its rooms: the meter page opens there.
    var openHalted: (MeterWalkStop) -> Void
    @EnvironmentObject private var campus: CampusModel

    var body: some View {
        // A stack even when there is nothing to show, so the question is kept from the start.
        VStack(alignment:.leading, spacing:0) { status }
            .onChange(of:campus.dormStepMeter, initial:true) { _, now in keepQuestion(now) }
    }

    private var line: DormStepMeter {
        if let preview { return preview }
        let now = campus.dormStepMeter
        if now == .hidden, campus.powerConfigured, asked.pick != nil, let question = asked.question { return .ask(question) }
        return now
    }

    private func keepQuestion(_ now: DormStepMeter) {
        guard !previewing, case .ask(let question) = now else { return }
        if question != asked.question { asked.pick = nil }
        asked.question = question
        asked.stamp = campus.powerQuestionStamp
    }

    @ViewBuilder private var status: some View {
        switch line {
        case .hidden: EmptyView()
        case .finding:
            HStack(spacing:8) {
                ProgressView().controlSize(.mini).tint(Theme.ink2).frame(width:12, height:12)
                Text(MeterPageText.finding).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
            }
            .padding(.top,18)
        case .ask(let question):
            VStack(alignment:.leading, spacing:0) {
                Text(question.text).scaledFont(17, .semibold).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityAddTraits(.isHeader)
                LocationChoiceList(choices:question.rows.map { LocationChoice(id:$0.id, title:$0.title, location:$0.location, voice:$0.spoken, opens:$0.picker != nil) },
                                   selection:Binding(get:{ asked.pick }, set:{ id in pick(id, in:question) }), compact:true)
                    .padding(.top,10)
                    .sensoryFeedback(.selection, trigger:asked.pick)
                if !previewing, let issue = campus.powerMatchIssue, issue != MeterPageText.stoppedIssue {
                    Text(MeterPageText.issue(issue)).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true).padding(.top,8)
                }
            }
            .padding(.top,28)
        case .failed(let text):
            VStack(alignment:.leading, spacing:0) {
                Text(text).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                Button(DormStepMeter.retry) { if !previewing { campus.matchPowerAutomatically() } }
                    .scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
                    // 44 pt to tap; the text sits 8 pt under the line above and the note 6 pt under it.
                    .frame(minHeight:44)
                    .padding(.vertical,-12).padding(.top,8)
                Text(DormStepMeter.skipNote).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.top,6)
            }
            .padding(.top,18)
        }
    }

    /// A row of the question picked: bound at once (another pick binds that one instead).
    private func pick(_ id: String?, in question: MeterQuestion) {
        guard let id, let row = question.rows.first(where:{ $0.id == id }) else { return }
        if let halted = row.picker {
            // Opens in the demos too: the page shows the stop as given.
            openHalted(halted)
            return
        }
        guard let candidate = row.candidate else { return }
        let before = asked.pick
        asked.pick = id
        guard !previewing else { return }
        let stamp = asked.stamp
        Task {
            if !(await campus.choosePower(PowerChoice(candidate:candidate, stamp:stamp))), asked.pick == id { asked.pick = before }
        }
    }
}
