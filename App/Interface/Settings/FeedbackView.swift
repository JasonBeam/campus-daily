import PhotosUI
import SwiftUI
import Core

/// 反馈问题: a sheet with the text, up to four screenshots the person picks (none by default),
/// 取消 and 发送. A failed send shows one fixed line, never the service's words.
struct FeedbackView: View {
    let endpoint: FeedbackEndpoint
    let http: HTTPClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @Environment(SampleMode.self) private var sample
    @Environment(\.campusServices) private var services
    /// 「附上调试记录」: off each time the form opens.
    @State private var attachLog = false
    /// The TestFlight log's lines, read when the form opens; empty outside TestFlight.
    @State private var logLines: [String] = []
    @State private var showingLog = false
    @State private var message = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    /// Picked photos still loading (an iCloud download, say): 发送 waits for them.
    @State private var loadingImages = false
    /// Picked photos that failed to download or decode, said under 添加截图.
    @State private var photoFailures = FeedbackPhotoFailures()
    @State private var sending = false
    @State private var failure: String?
    @State private var sent = false

    private var issue: FeedbackDraft.Issue? { FeedbackDraft.issue(message:message, imageCount:images.count) }
    private var canSend: Bool {
        !sending && FeedbackDraft.canSend(message:message, imageCount:images.count, loadingImages:loadingImages)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("遇到了什么问题，或者想要什么功能？", text:$message, axis:.vertical)
                        .lineLimit(5 ... 12)
                        .accessibilityIdentifier("feedbackText")
                } footer: {
                    if let line = FeedbackText.issue(issue) {
                        Text(line).foregroundStyle(Theme.redText).accessibilityIdentifier("feedbackTooLong")
                    }
                }
                Section {
                    if !images.isEmpty { thumbnails }
                    PhotosPicker(selection:$pickerItems,
                                 maxSelectionCount:max(1, FeedbackDraft.maximumImages - images.count),
                                 matching:.images) {
                        HStack {
                            Label("添加截图", systemImage:"photo.on.rectangle")
                            Spacer()
                            if loadingImages {
                                ProgressView().accessibilityIdentifier("feedbackLoadingImages")
                            }
                        }
                    }
                    .disabled(sending || loadingImages || images.count >= FeedbackDraft.maximumImages)
                    .accessibilityIdentifier("feedbackAddScreenshot")
                } footer: {
                    VStack(alignment:.leading, spacing:6) {
                        if let line = photoFailures.line {
                            failureLine(line).accessibilityIdentifier("feedbackPhotoFailure")
                        }
                        Text("最多 4 张。会附上 App 版本、手机型号和系统版本，不带账号和余额。")
                    }
                }
                if !logLines.isEmpty { debugLogSection }
                if let failure {
                    Section {
                        failureLine(failure).accessibilityIdentifier("feedbackFailure")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NativeTheme.background.ignoresSafeArea())
            .navigationTitle("反馈问题").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("取消") { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button(sending ? "正在发送…" : "发送") { send() }
                        .fontWeight(.semibold)
                        .disabled(!canSend)
                        .accessibilityIdentifier("feedbackSend")
                }
            }
            .onChange(of:pickerItems) { _, items in
                // Set before the task starts, so 发送 is off from the moment the picker closes.
                if !items.isEmpty { loadingImages = true }
                Task { await load(items) }
            }
            .onAppear { logLines = Self.readLog(services.debugLog) }
            .task {
                // Shown once launch knows this is TestFlight (`LaunchDebugLog`).
                await services.debugLog.waitUntilResolved()
                logLines = Self.readLog(services.debugLog)
            }
            .sheet(isPresented:$showingLog) { debugLogPreview }
            .alert("发出去了", isPresented:$sent) {
                Button("好") { dismiss() }
            } message: {
                Text("谢谢反馈。")
            }
        }
        .tint(NativeTheme.tint)
        .typesettingLanguage(Theme.typesetting)
        .interactiveDismissDisabled(sending)
    }

    /// A failed send or photos not added, in `notice` as each theme shows problems: 清爽's issue
    /// line (icon, one-line words in `notice`), 暖橙's footnote like 电费's.
    @ViewBuilder private func failureLine(_ line: String) -> some View {
        if appTheme == .clear {
            ClearLaundryIssueLines(lines:[line])
        } else {
            Text(line).font(.footnote).foregroundStyle(NativeTheme.notice)
        }
    }

    /// The log's lines once every line queued before is written (`flush`); none outside TestFlight.
    static func readLog(_ log: any DebugLogSink) -> [String] {
        guard log.isEnabled else { return [] }
        log.flush()
        return log.lines()
    }

    /// TestFlight only, with something in the log: off unless turned on for this message.
    private var debugLogSection: some View {
        Section {
            Toggle(FeedbackLogText.toggle, isOn:$attachLog)
                .disabled(sending)
                .accessibilityIdentifier("feedbackAttachLog")
        } footer: {
            VStack(alignment:.leading, spacing:6) {
                Text(FeedbackLogText.footer)
                Button(FeedbackLogText.showButton) { logLines = Self.readLog(services.debugLog); showingLog = true }
                    .font(.footnote)
                    .accessibilityIdentifier("feedbackShowLog")
            }
        }
    }

    /// Exactly the text that would go: the typed words, then the log as it rides along.
    private var debugLogPreview: some View {
        NavigationStack {
            ScrollView {
                Text(DebugLogReport.message(message, lines:logLines))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth:.infinity, alignment:.leading)
                    .padding()
            }
            .navigationTitle(FeedbackLogText.previewTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.confirmationAction) { Button("好") { showingLog = false } }
            }
        }
        .accessibilityIdentifier("feedbackLogPreview")
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing:8) {
                ForEach(images.indices, id:\.self) { index in
                    Image(uiImage:images[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width:72, height:72)
                        .clipShape(RoundedRectangle(cornerRadius:8))
                        .overlay(alignment:.topTrailing) {
                            Button {
                                images.remove(at:index)
                                photoFailures.removed(remaining:images.count)
                            } label: {
                                Image(systemName:"xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(4)
                            .disabled(sending)
                            .accessibilityLabel("删掉这张截图")
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { loadingImages = false }
        var added = 0, failed = 0
        for item in items where images.count < FeedbackDraft.maximumImages {
            guard let data = try? await item.loadTransferable(type:Data.self),
                  let image = UIImage(data:data)
            else { failed += 1; continue }
            images.append(image)
            added += 1
        }
        photoFailures.finishedLoading(added:added, failed:failed)
        pickerItems = []
    }

    private func send() {
        guard canSend else { return }
        // The sample sends nothing: the form stays as it is.
        guard !sample.isActive else { sample.perform(.sendFeedback) {}; return }
        sending = true
        failure = nil
        Task {
            do {
                // Read again: what happened while the form was open goes too. Off: nothing more.
                let lines = attachLog && services.debugLog.isEnabled ? Self.readLog(services.debugLog) : nil
                try await FeedbackReporter.send(message:message, images:images, to:endpoint, http:http, debugLog:lines)
                sent = true
            } catch {
                failure = FeedbackText.failure(error)
            }
            sending = false
        }
    }
}

/// The words for 「附上调试记录」 on 反馈问题.
enum FeedbackLogText {
    static let toggle = "附上调试记录"
    static let footer = "会带上最近的操作步骤：点了什么、走到哪一步、请求成没成。不带密码、账号、学号、姓名和宿舍，机器和订单只记一串代号。"
    static let showButton = "看看内容"
    static let previewTitle = "将要发出的调试记录"
}
