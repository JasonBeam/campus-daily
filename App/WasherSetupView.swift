import SwiftUI
import PhotosUI
import Vision
import VisionKit
import WaterCore

struct WasherSetupView: View {
    @EnvironmentObject private var laundry: LaundryModel
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var alias = ""
    @State private var issue: String?
    @State private var photoBusy = false
    @State private var login = false
    var body: some View {
        Form {
            Section {
                LabeledContent("U净账号",value:laundry.accountConnected ? "已登录" : "尚未登录")
                Button(laundry.accountConnected ? "更新 U净登录" : "登录 U净") { login = true }
                    .disabled(!laundry.mayImport).accessibilityIdentifier("ujingLoginEntry")
            }
            Section("常用洗衣机") {
                ForEach(laundry.savedMachines) { item in
                    Button {
                        do { try laundry.selectMachine(item); Task { await laundry.refresh(force:true) } }
                        catch { issue = (error as? LocalizedError)?.errorDescription }
                    } label: {
                        HStack {
                            Label(item.name,systemImage:"washer")
                            Spacer()
                            if laundry.selectedMachineID == item.id { Image(systemName:"checkmark").accessibilityLabel("当前机器") }
                        }
                    }.disabled(!laundry.mayImport).accessibilityIdentifier("savedWasher-" + item.id)
                }
                if laundry.savedMachines.isEmpty { Text("扫一次机身二维码，即可保存常用机器").foregroundStyle(.secondary) }
            }
            Section {
                if DataScannerViewController.isSupported {
                    Button { camera = true } label: { Label("扫描机身二维码",systemImage:"qrcode.viewfinder") }
                        .disabled(!laundry.accountConnected || !laundry.mayImport || photoBusy).accessibilityIdentifier("scanWasherQR")
                }
                PhotosPicker(selection:$photo,matching:.images) { Label("从照片识别",systemImage:"photo") }
                    .disabled(!laundry.accountConnected || !laundry.mayImport || photoBusy).accessibilityIdentifier("washerQRPhoto")
            } header: { Text("添加机器") } footer: { Text("只读取机器信息，不下单或启动。已有未结束订单时不能切换机器。") }
            if laundry.loading || photoBusy { Section { HStack { ProgressView(); Text("正在识别机器…") } } }
            if let value = laundry.candidate {
                Section("核对并保存") {
                    LabeledContent("机器",value:"\(value.deviceNo)号 · \(value.storeName)")
                    LabeledContent("当前状态",value:value.stateLabel)
                    TextField("例如：本层 1 号机",text:$alias).accessibilityIdentifier("washerAlias")
                    Button("保存为常用机器") {
                        do { try laundry.savePreparedMachine(name:alias); issue = nil }
                        catch { issue = (error as? LocalizedError)?.errorDescription }
                    }.disabled(!laundry.mayImport || alias.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveScannedWasher")
                }
            }
            if let text = issue ?? laundry.issue { Section { Text(text).font(.footnote).foregroundStyle(.orange) } }
        }.navigationTitle("常用洗衣机").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$login) { UjingLoginView() }
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
                Task {
                    defer { photoBusy = false; photo = nil }
                    do {
                        guard let data = try await item.loadTransferable(type:Data.self), data.count <= 20_000_000 else { throw LaundryError.configuration }
                        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                        try VNImageRequestHandler(data:data).perform([request])
                        let codes = Set((request.results ?? []).compactMap(\.payloadStringValue))
                        guard codes.count == 1, let text = codes.first else { issue = "请选择只包含一台洗衣机二维码的清晰照片"; return }
                        resolve(text)
                    } catch { issue = "照片中未识别到有效的洗衣机二维码" }
                }
            }
    }
    private func resolve(_ text: String) {
        do { try WasherQRCode.validate(text) }
        catch { issue = "请扫描 U净洗衣机机身二维码"; return }
        issue = nil
        Task {
            await laundry.prepareMachine(qrCode:text)
            if let value = laundry.candidate {
                alias = laundry.savedMachines.first(where:{ $0.id == value.deviceId })?.name ?? "\(value.deviceNo)号洗衣机"
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
            catch { failed("相机暂不可用，请允许相机访问，或从照片识别") }
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
            guard !completed else { return }; completed = true; failed("相机暂不可用，请从照片识别")
        }
    }
}
