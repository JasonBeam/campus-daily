import SwiftUI
import Core

struct CampusPowerSetupView: View {
    /// Opens here instead of where the lookup stopped (an apartment that halted before its rooms).
    var start: MeterWalkStop?
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: [PowerNode] = []
    @State private var meters: [Meter] = []
    @State private var path: [PowerNode] = []
    /// The level `options` belong to (nil before the first list is read).
    @State private var level: MeterLevel?
    /// Rows offered first with 「可能是这个」.
    @State private var suggested: [String] = []
    /// Showing where the automatic lookup stopped (not walked away from yet).
    @State private var atStop = false
    /// Opened where the lookup ended unfinished (one of several apartments not read).
    @State private var unread = false
    @State private var busy = false
    @State private var issue: String?
    @State private var search = ""
    /// Who was signed in when the picker (re)opened: a pick after someone else signed in is refused.
    @State private var stamp: Int?
    var body: some View {
        List {
            if unreadShown {
                // One of several apartments not read: the matched levels, then only the message
                // and 「再找一次电表」, no list.
                pathCard
                AutomaticPowerSection(onMeterPage:true)
            } else {
                AutomaticPowerSection(onMeterPage:true)
                pathCard
                if busy { Text("正在读取电表信息…").foregroundStyle(.secondary).listRowBackground(Theme.group) }
                if let issue { Text(issue).foregroundStyle(NativeTheme.notice).font(.footnote).listRowBackground(Theme.group) }
                if meters.isEmpty, atStop, let question = campus.powerQuestion {
                    // Rooms of the dorm's name in several apartments: which one. A tap binds it.
                    Section {
                        ForEach(question.rows) { row in
                            Button {
                                if let candidate = row.candidate {
                                    Task { if await campus.choosePower(PowerChoice(candidate:candidate, stamp:campus.powerQuestionStamp)) { dismiss() } }
                                } else if let halted = row.picker {
                                    // Where that apartment halted, with that level's list.
                                    show(halted); atStop = false
                                }
                            } label: {
                                HStack(spacing:8) {
                                    VStack(alignment:.leading, spacing:2) {
                                        Text(row.title)
                                        Text(row.location).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                                            .fixedSize(horizontal:false, vertical:true)
                                    }
                                    Spacer(minLength:0)
                                    // Only a halted apartment opens a list; a room binds at the tap.
                                    if row.picker != nil { RowChevron() }
                                }
                            }
                            .disabled(busy || campus.matchingPower)
                            .accessibilityLabel(row.spoken)
                        }.listRowBackground(Theme.group)
                    } header: {
                        HStack(spacing:6) {
                            Text(question.text).textCase(nil).fixedSize(horizontal:false, vertical:true)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength:0)
                            if campus.matchingPower { ProgressView().controlSize(.mini).frame(width:12, height:12) }
                        }
                    }
                } else if meters.isEmpty {
                    Section {
                        ForEach(MeterPageText.rows(options.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) },
                                                   suggested:suggested)) { row in
                            Button { Task { await choose(row.node) } } label: {
                                VStack(alignment:.leading, spacing:2) {
                                    Text(row.node.name)
                                    if row.suggested {
                                        Text(MeterPageText.suggestion).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                                    }
                                }
                            }.disabled(busy)
                        }.listRowBackground(Theme.group)
                    } header: {
                        HStack(spacing:6) {
                            Text(level.map(MeterPageText.header) ?? "选择位置")
                            Spacer(minLength:0)
                            // The lookup is running again: this list stays until it answers.
                            if campus.matchingPower && atStop { ProgressView().controlSize(.mini).frame(width:12, height:12) }
                        }
                    }
                } else {
                    Section("核对电表") {
                        ForEach(meters, id:\.comAddress) { meter in
                            Button {
                                guard let room = path.last, let stamp else { return }
                                Task {
                                    do { try await campus.chooseMeter(nodeID:room.id, meter:meter, path:path.map(\.name), since:stamp); dismiss() }
                                    catch { issue = "没保存上，再试一次。" }
                                }
                            } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    Text(meter.name).font(.headline)
                                    Text("剩余 \(NSDecimalNumber(decimal:meter.remainingKWh ?? 0).stringValue) 度 · 电费 \(NSDecimalNumber(decimal:meter.leftMoney?.yuan ?? 0).stringValue) 元")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text("确认是我的宿舍并保存").font(.footnote)
                                }.padding(.vertical,8)
                            }.disabled(busy)
                        }.listRowBackground(Theme.group)
                    }
                }
            }
        }.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea()).tint(NativeTheme.tint)
            .navigationTitle(MeterPageText.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text:$search,prompt:MeterPageText.searchPrompt)
            .task { await open() }
            // The lookup stopped again (it ran once more meanwhile): shown if the user is still there.
            .onChange(of:campus.powerStop) { _, stop in
                // At the stop, or on the untouched first list (opened while nothing was stopped).
                guard atStop || path.isEmpty && level == .campus, !busy, let stop, !stop.options.isEmpty else { return }
                show(stop)
            }
    }
    /// The matched levels with 「重选」 (or the prompt before any).
    private var pathCard: some View {
        Section {
            if path.isEmpty {
                LocationPathHeader(path:[], placeholder:MeterPageText.pickerPrompt)
            } else {
                HStack(spacing:12) {
                    LocationPathHeader(path:[MeterPageText.matchedLine(path)])
                    Spacer(minLength:8)
                    Button(MeterPageText.rechoose) { Task { await loadRoot() } }
                        .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
                        .buttonStyle(.borderless).disabled(busy)
                        .accessibilityIdentifier("meterRechoose")
                }
            }
        }.listRowBackground(Theme.group)
    }
    /// Unfinished and not walked away from (「重选」 opens the list from the campuses).
    private var unreadShown: Bool { unread && campus.powerUnfinished != nil }
    /// Where the lookup stopped (or ended unfinished), else the campuses.
    private func open() async {
        // Nil once a meter is bound (`MeterLookupGate.pageStop`): the page starts at the campuses.
        if let start {
            stamp = await campus.personStamp()
            show(start); atStop = false
        } else if let stop = campus.powerStop {
            stamp = await campus.personStamp()
            show(stop)
        } else if let unfinished = campus.powerUnfinished {
            stamp = await campus.personStamp()
            show(unfinished)
            unread = true
        } else {
            await loadRoot()
        }
    }
    private func show(_ stop: MeterWalkStop) {
        path = stop.path; options = stop.options; level = stop.level; suggested = stop.suggested
        meters = []; issue = nil; search = ""; atStop = true; unread = false
    }
    private func loadRoot() async {
        guard !busy, campus.configured else { issue = "先登录学校账号。"; return }
        busy = true; issue = nil; path = []; meters = []; search = ""; atStop = false; unread = false; level = nil; suggested = []
        defer { busy = false }
        stamp = await campus.personStamp()
        do {
            options = try await campus.directory(parent:nil)
            level = .campus
            suggested = MeterPageText.suggested(options, at:.campus, for:campus.address)
        }
        catch { issue = MeterPageText.issue(error, otherwise:"位置列表读取失败") }
    }
    private func choose(_ option: PowerNode) async {
        guard !busy, campus.configured else { return }
        busy = true; issue = nil; search = ""
        defer { busy = false }
        do {
            let children = try await campus.directory(parent:option.id)
            path.append(option); options = children; atStop = false
            let next = MeterLevel.next(after:level, options:children)
            level = next
            suggested = MeterPageText.suggested(children, at:next, for:campus.address)
            if children.isEmpty {
                meters = try await campus.meterRows(nodeID:option.id)
                if meters.isEmpty { issue = "这里没有电表，重新选一下位置。" }
            }
        } catch { issue = MeterPageText.issue(error, otherwise:"电表没读到，再试一次。") }
    }
}

/// Same same-name choice as onboarding, on the meter settings page.
struct AutomaticPowerSection: View {
    /// On the meter page: a slow school reads 「学校那边太慢了，等一下再找。」 (`MeterPageText`).
    var onMeterPage = false
    @EnvironmentObject private var campus: CampusModel
    @State private var selection: String?
    var body: some View {
        // On the meter page at a stopped level the level's own list is the answer: a lookup
        // running again shows only its spinner by the list header; a failure is said here.
        let atStop = onMeterPage && campus.powerStop != nil && campus.powerChoices.isEmpty && !campus.powerConfigured
        if atStop {
            if let note = MeterPageText.noteAtStop(finding:campus.matchingPower, issue:campus.powerMatchIssue) {
                Section("电表") {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                    Button("再找一次电表") {campus.matchPowerAutomatically()}
                }.listRowBackground(Theme.group)
            }
        } else if campus.matchingPower || !campus.powerChoices.isEmpty || campus.powerMatchIssue != nil || campus.powerConfigured {
            Section(campus.powerChoices.isEmpty ? "电表" : SameNameText.titleLead + SameNameText.titleAccent + SameNameText.titleTail) {
                if campus.matchingPower {
                    if onMeterPage { Text(MeterPageText.finding).foregroundStyle(Theme.ink2) }
                    else { Label("正在找电表，可以先保存宿舍。",systemImage:"bolt") }
                }
                else if !campus.powerChoices.isEmpty {
                    Text(SameNameText.hint(campus.powerChoices.map(\.choice)))
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                    LocationChoiceList(choices:campus.powerChoices.map(\.choice), selection:$selection)
                    Button("就是这间") {
                        if let candidate = campus.powerChoices.first(where:{ $0.id == selection }) {
                            Task { await campus.choosePower(candidate) }
                        } else { selection = nil }
                    }
                    .disabled(selection == nil || campus.matchingPower)
                    .accessibilityIdentifier("powerApartmentConfirm")
                } else if campus.powerConfigured {Label("电表已保存",systemImage:"checkmark.circle").foregroundStyle(Theme.ink2)}
                if let issue = campus.powerMatchIssue {
                    Text(onMeterPage ? MeterPageText.issue(issue) : issue).font(.footnote).foregroundStyle(.secondary)
                    Button("再找一次电表") {campus.matchPowerAutomatically()}
                }
            }
            .listRowBackground(onMeterPage ? Theme.group : nil)
            // A new list: an earlier pick may no longer be in it.
            .onChange(of:campus.powerChoices) { _, _ in selection = nil }
        }
    }
}
