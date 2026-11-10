import SwiftUI
import PhotosUI
import Vision
import VisionKit
import Core

struct WasherSetupView: View {
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    /// After a machine is saved or switched; nil goes back a page. Home pushes the laundry page
    /// over it when it was opened from home (`WasherSetupExit.path`).
    var onDone: (() -> Void)?
    /// 清爽: the 「学校洗衣机」 switch, at the bottom of this page (清爽's 设置 has no row for it).
    var laundrySwitch: SchoolLaundrySwitch? = nil
    #if DEBUG
    /// campusdaily://demo/washer/...: synthetic account and machines; nothing is changed.
    var preview: WasherSetupDemo?
    #endif
    @State private var camera = false
    @State private var photoPicker = false
    @State private var photo: PhotosPickerItem?
    @State private var alias = ""
    @State private var issue: String?
    @State private var photoBusy = false
    /// The picked photo being read; cancelled when the page goes, so a late result is dropped.
    @State private var photoTask: Task<Void, Never>?
    @State private var login = false
    /// What was tapped while signed out: opened once the U净 login goes through.
    @State private var pending: WasherSetupFlow.Method?

    private var signedIn: Bool {
        #if DEBUG
        if let preview { return preview.signedIn }
        #endif
        return laundry.accountConnected
    }
    private var machines: [SavedWasher] {
        #if DEBUG
        if let preview { return preview.machines }
        #endif
        return laundry.savedMachines
    }
    private var selectedID: String? {
        #if DEBUG
        if let preview { return preview.machines.first?.id }
        #endif
        return laundry.selectedMachineID
    }
    /// A scanned code or a picked photo being read (or the machine re-read after a switch).
    private var reading: Bool { laundry.loading || photoBusy }
    private var addDisabled: Bool { WasherSetupFlow.addDisabled(mayImport:laundry.mayImport, busy:photoBusy) }
    private var isPreview: Bool {
        #if DEBUG
        preview != nil
        #else
        false
        #endif
    }

    var body: some View {
        Form {
            if let guide = appTheme == .clear ? Optional(signedIn ? WasherSetupGuide.scan : .signIn)
                : WasherSetupGuide.card(signedIn:signedIn, hasSavedMachine:!machines.isEmpty) {
                Section {
                    Text(guide == .signIn ? "第一步：用手机号登录 U净" : "下一步：扫描机身二维码")
                        .font(.headline)
                    Text(guide == .signIn ? "收到验证码后登录，再扫一次二维码，以后就能直接找到机器。" : "机器名称会自动填写，核对后点保存即可。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if guide == .signIn {
                        Button("登录 U净") { pending = nil; login = true }
                            .disabled(!laundry.mayLogin).accessibilityIdentifier("ujingLoginEntry")
                    } else if appTheme == .clear {
                        Button("更新 U净登录") { if !isPreview { pending = nil; login = true } }
                            .disabled(!laundry.mayLogin).accessibilityIdentifier("ujingLoginEntry")
                    }
                }
            }
            Section("常用洗衣机") {
                ForEach(machines) { item in
                    Button { choose(item) } label: {
                        HStack {
                            Label(item.name,systemImage:"washer")
                            Spacer()
                            if selectedID == item.id { Image(systemName:"checkmark").accessibilityLabel("当前机器") }
                        }
                    }.disabled(!laundry.mayImport).accessibilityIdentifier("savedWasher-" + item.id)
                }
                if machines.isEmpty { Text("扫一次机身二维码，即可保存常用机器").foregroundStyle(.secondary) }
            }
            Section {
                if DataScannerViewController.isSupported {
                    Button { add(.scan) } label: { Label("扫描机身二维码",systemImage:"qrcode.viewfinder") }
                        .disabled(addDisabled).accessibilityIdentifier("scanWasherQR")
                }
                Button { add(.photo) } label: { Label("从照片识别",systemImage:"photo") }
                    .disabled(addDisabled).accessibilityIdentifier("washerQRPhoto")
            } header: { Text("添加机器") } footer: { Text("只读取机器信息，不下单或启动。已有未结束订单时不能切换机器。") }
            if reading { Section { HStack { ProgressView(); Text("正在识别机器…") } } }
            if let value = laundry.candidate {
                Section("核对并保存") {
                    LabeledContent("机器",value:"\(value.deviceNo)号 · \(value.storeName)")
                    LabeledContent("当前状态",value:value.stateLabel)
                    TextField("机器名称（已自动填写，可修改）",text:$alias).accessibilityIdentifier("washerAlias")
                    Button("保存为常用机器") {
                        do { try laundry.savePreparedMachine(name:alias); issue = nil; finish() }
                        catch { issue = Self.text(error) }
                    }.disabled(!laundry.mayImport || alias.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveScannedWasher")
                }
            }
            if let text = issue ?? laundry.issue {
                Section {
                    Text(text).font(.footnote).foregroundStyle(NativeTheme.notice)
                    if laundry.sessionExpired && !isPreview {
                        Button(UjingAccountText.relogin) { pending = nil; login = true }
                            .disabled(!laundry.mayLogin).accessibilityIdentifier("ujingRelogin")
                    }
                }
            }
            if let laundrySwitch {
                Section {
                    Toggle(isOn:laundrySwitch.binding) {
                        Label(SchoolLaundryPreference.title, systemImage:"switch.2")
                    }
                    .tint(.green)
                    .disabled(laundrySwitch.locked)
                    .accessibilityIdentifier("schoolLaundrySwitch")
                } footer: {
                    Text(SchoolLaundryPreference.footer(isOn:laundrySwitch.isOn, locked:laundrySwitch.locked))
                }
            }
            if signedIn { accountSection }
        }.scrollContentBackground(.hidden).background(NativeTheme.background).tint(NativeTheme.tint)
            // The reading row and the machine to check come in while the scanner sheet goes down:
            // animated, so the rows below slide instead of jumping.
            .animation(.default, value:reading)
            .animation(.default, value:laundry.candidate)
            .navigationTitle("常用洗衣机").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$login, onDismiss:continueAfterLogin) { UjingLoginView() }
            .photosPicker(isPresented:$photoPicker, selection:$photo, matching:.images)
            .sheet(isPresented:$camera) {
                NavigationStack {
                    WasherCamera { text in camera = false; resolve(text) } failed: { message in camera = false; issue = message }
                        .navigationTitle("扫描二维码").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { camera = false } } }
                }
            }
            .onChange(of:photo) { _, item in
                guard let item else { return }
                photoBusy = true; issue = nil
                photoTask?.cancel()
                photoTask = Task {
                    defer { photoBusy = false; photo = nil }
                    do {
                        guard let data = try await item.loadTransferable(type:Data.self), data.count <= 20_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                        let payloads = try await Self.qrPayloads(in:data)
                        // Left the page while the photo was read: the machine is not looked up.
                        try Task.checkCancellation()
                        let codes = WasherPhotoCodes(payloads:payloads)
                        guard case .one(let text) = codes else { issue = codes.message; return }
                        resolve(text)
                    } catch is CancellationError {
                    } catch { issue = "没认出这台洗衣机，换个角度再扫一次。" }
                }
            }
            .onDisappear { photoTask?.cancel(); photoTask = nil }
    }

    @ViewBuilder private var accountSection: some View {
        #if DEBUG
        if let preview {
            UjingAccountSection(mobile:preview.mobile, refusal:preview.orderOpen ? .orderOpen : nil, signOut:{})
        } else {
            UjingAccountSection(mobile:laundry.ujingMobile, refusal:laundry.signOutRefusal, failed:laundry.signOutFailed,
                            signOut:laundry.signOut)
        }
        #else
        UjingAccountSection(mobile:laundry.ujingMobile, refusal:laundry.signOutRefusal, failed:laundry.signOutFailed,
                            signOut:laundry.signOut)
        #endif
    }

    /// 扫描机身二维码 / 从照片识别. Signed out: the U净 login first, then straight on.
    private func add(_ method: WasherSetupFlow.Method) {
        if isPreview { return }
        switch WasherSetupFlow.tap(method, signedIn:signedIn) {
        case .open(let method): open(method)
        case .signIn(let then): pending = then; login = true
        }
    }

    private func open(_ method: WasherSetupFlow.Method) {
        switch method {
        case .scan: camera = true
        case .photo: photoPicker = true
        }
    }

    /// The login sheet has gone: on to what was tapped, or nothing when it was cancelled.
    private func continueAfterLogin() {
        let next = WasherSetupFlow.afterLogin(pending:pending, signedIn:laundry.accountConnected)
        pending = nil
        if let next { open(next) }
    }

    private func choose(_ item: SavedWasher) {
        if isPreview { return }
        do {
            try laundry.selectMachine(item); issue = nil
            Task { await laundry.refresh(force:true) }
            finish()
        } catch { issue = Self.text(error) }
    }

    /// Saved or switched: a success tap and back (or wherever the caller sends it).
    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let onDone { onDone() } else { dismiss() }
    }

    private static func text(_ error: Error) -> String {
        (error as? WasherSetupRefusal)?.message ?? AppErrorText.text(error)
    }

    /// Reads every QR code in the photo off the main actor: a large photo takes a while.
    private nonisolated static func qrPayloads(in data: Data) async throws -> [String?] {
        try await Task.detached(priority:.userInitiated) {
            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
            try VNImageRequestHandler(data:data).perform([request])
            return (request.results ?? []).map(\.payloadStringValue)
        }.value
    }

    private func resolve(_ text: String) {
        guard UjingInput.isWasherQR(text) else { issue = "扫洗衣机机身上的码。"; return }
        issue = nil
        Task {
            await laundry.prepareMachine(qrCode:text)
            if let value = laundry.candidate {
                alias = laundry.savedMachines.first(where:{ $0.id == value.deviceID })?.name ?? "\(value.deviceNo)号洗衣机"
            }
        }
    }
}

private struct WasherCamera: UIViewControllerRepresentable {
    let receive: (String) -> Void
    let failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(receive:receive,failed:failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes:[.barcode(symbologies:[.qr])],
            qualityLevel:.balanced,recognizesMultipleItems:false,isHighFrameRateTrackingEnabled:false,
            isPinchToZoomEnabled:true,isGuidanceEnabled:true,isHighlightingEnabled:true)
        scanner.delegate = context.coordinator
        DispatchQueue.main.async {
            do { try scanner.startScanning() }
            catch { failed("相机用不了。去设置里允许校日常用相机，或者从照片识别。") }
        }
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) { uiViewController.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let receive: (String) -> Void
        let failed: (String) -> Void
        var completed = false
        init(receive: @escaping (String)->Void, failed: @escaping (String)->Void) { self.receive = receive; self.failed = failed }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !completed else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    completed = true; dataScanner.stopScanning(); receive(text); return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !completed else { return }; completed = true; failed("相机用不了，从照片识别吧。")
        }
    }
}
