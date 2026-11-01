import Foundation
@preconcurrency import CoreBluetooth
import Core

struct VerifiedShowerDevice {
    let id: String
    let name: String
    let machineID: String
    let rssi: Int?
    let nearbyCount: Int
    let verifiedAt: Date
}

/// One pending transport step at a time. Each wait reserves a token; late timers and cancel handlers
/// pass their token and can only finish the wait they were created for, never the next step.
@MainActor final class WaitSlot {
    private var continuation: CheckedContinuation<Void, Error>?
    private var generation = 0
    var isWaiting: Bool { continuation != nil }
    func reserve() -> Int { generation &+= 1; return generation }
    func attach(_ continuation: CheckedContinuation<Void, Error>, token: Int) {
        guard token == generation, self.continuation == nil else {
            continuation.resume(throwing: ShowerDeviceError.interrupted); return
        }
        self.continuation = continuation
    }
    func accepts(_ token: Int?) -> Bool { token == nil || token == generation }
    @discardableResult func complete(_ result: Result<Void, Error>, token: Int? = nil) -> Bool {
        guard accepts(token), let continuation else { return false }
        self.continuation = nil
        continuation.resume(with: result)
        return true
    }
}

// CoreBluetooth delegates are delivered on the explicit main queue below.
@MainActor final class BluetoothTransport: NSObject, ShowerTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var retiring: CBPeripheral?
    private var targets: [UUID: CBPeripheral] = [:]
    private var signalLevels: [UUID: Int] = [:]
    private var targetName = ""
    private var observedIDs = Set<UUID>()
    private var notify: CBCharacteristic?
    private var write: CBCharacteristic?
    private var decoder = ShowerFrameAssembler()
    private var pendingFrame: Data?
    private var channelError: ShowerDeviceError?
    private var writeAcknowledged = false
    private var step: String?
    private let waiter = WaitSlot()
    private var timer: Task<Void, Never>?

    private func wait(_ name: String, seconds: Double = 15, begin: () -> Void) async throws {
        try Task.checkCancellation()
        guard !waiter.isWaiting else { throw ShowerDeviceError.busy }
        // The timer and cancel handler only ever finish this wait (token), never a later step.
        let token = waiter.reserve()
        ShowerDiagnosticReport.record("ble." + name)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                step = name
                waiter.attach(continuation, token: token)
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.complete(.failure(ShowerDeviceError.timedOut), token: token)
                }
                begin()
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.complete(.failure(ShowerDeviceError.interrupted), token: token) } })
    }
    /// `token` nil: a device callback for the current step.
    private func complete(_ result: Result<Void, Error>, token: Int? = nil) {
        guard waiter.accepts(token) else { return }
        step = nil
        timer?.cancel(); timer = nil
        waiter.complete(result)
    }
    private func prepare(bleName: String) async throws {
        if manager == nil { manager = CBCentralManager(delegate: self, queue: .main) }
        if manager.state == .unknown || manager.state == .resetting {
            try await wait("power") {}
        }
        guard manager.state == .poweredOn else { throw ShowerDeviceError.bluetoothOff }
        if let old = retiring, old.state != .disconnected {
            try await wait("disconnect") { manager.cancelPeripheralConnection(old) }
        }
        retiring = nil
        targetName = bleName
    }
    private func scanTargets() async throws {
        targets.removeAll(); observedIDs.removeAll(); signalLevels.removeAll()
        // Some water controllers omit FFE0 from advertising, so inspect names first.
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        do { try await Task.sleep(for: .seconds(12)) }
        catch { manager.stopScan(); throw ShowerDeviceError.interrupted }
        manager.stopScan()
    }
    private func recordScan(remembered: String?, scanSeconds: Int = 12, cachedPeripheral: Bool = false) {
        let object: [String:Any] = ["observedAt":ISO8601DateFormatter().string(from:Date()),"scanSeconds":scanSeconds,
            "observedCount":observedIDs.count,"matchingCount":targets.count,
            "rememberedFound":cachedPeripheral || (remembered.map { id in targets.keys.contains { $0.uuidString == id } } ?? false),
            "cachedPeripheralUsed":cachedPeripheral]
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WaterSession",isDirectory:true)
        if let bytes = try? JSONSerialization.data(withJSONObject:object) {
            try? bytes.write(to:folder.appendingPathComponent("last-scan.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    private func establish(_ chosen: CBPeripheral) async throws -> String {
        peripheral = chosen
        chosen.delegate = self
        if chosen.state != .connected { try await wait("connect") { manager.connect(chosen) } }
        try await wait("service") { chosen.discoverServices([CBUUID(string: ShowerFrames.serviceUUID)]) }
        guard let service = chosen.services?.first(where: { $0.uuid == CBUUID(string: ShowerFrames.serviceUUID) }) else {
            throw ShowerDeviceError.disconnected
        }
        try await wait("characteristics") {
            chosen.discoverCharacteristics([CBUUID(string: ShowerFrames.notifyUUID), CBUUID(string: ShowerFrames.writeUUID)], for: service)
        }
        notify = service.characteristics?.first { $0.uuid == CBUUID(string: ShowerFrames.notifyUUID) }
        write = service.characteristics?.first { $0.uuid == CBUUID(string: ShowerFrames.writeUUID) }
        guard let notify, let write, notify.properties.contains(.notify), write.properties.contains(.write) else {
            throw ShowerDeviceError.disconnected
        }
        decoder = ShowerFrameAssembler(); pendingFrame = nil; channelError = nil
        try await wait("subscribe") { chosen.setNotifyValue(true, for: notify) }
        return chosen.identifier.uuidString
    }
    private func abandon(_ chosen: CBPeripheral) async {
        if chosen.state != .disconnected {
            retiring = chosen
            if peripheral === chosen { peripheral = nil }
            if Task.isCancelled { manager.cancelPeripheralConnection(chosen) }
            else { try? await wait("disconnect", seconds:4) { manager.cancelPeripheralConnection(chosen) } }
        }
        if peripheral === chosen { peripheral = nil }
        if retiring === chosen { retiring = nil }
        chosen.delegate = nil
        write = nil; notify = nil
    }
    func verifiedInformation(id: String, machineID: String) -> VerifiedShowerDevice {
        VerifiedShowerDevice(id:id,name:targetName,machineID:machineID.uppercased(),rssi:UUID(uuidString:id).flatMap { signalLevels[$0] },nearbyCount:targets.count,verifiedAt:Date())
    }
    /// Read-only scan for the 连接检查 screen: how many controllers carry this name nearby.
    func inspect(bleName: String, remembered: String?) async throws -> Int {
        try await prepare(bleName:bleName)
        try await scanTargets()
        recordScan(remembered:remembered)
        return targets.count
    }
    func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        try await prepare(bleName:bleName)
        // Reuse the live link (the official client keeps it after authorization).
        if let current = peripheral, current.state == .connected, write != nil, notify != nil,
           required == nil || current.identifier.uuidString == required {
            return current.identifier.uuidString
        }
        if let current = peripheral { await abandon(current) }
        let remembered = required ?? preferred
        if let remembered, let uuid = UUID(uuidString:remembered),
           let cached = manager.retrievePeripherals(withIdentifiers:[uuid]).first {
            targets.removeAll(); observedIDs.removeAll()
            do {
                let id = try await establish(cached)
                recordScan(remembered:remembered,scanSeconds:0,cachedPeripheral:true)
                return id
            } catch {
                await abandon(cached)
                // Connecting by remembered CoreBluetooth ID is only a fast path. If it fails,
                // rescan and keep the exact/preferred-device selection rules.
            }
        }
        try await scanTargets()
        recordScan(remembered:remembered)
        let id: String
        do {
            id = try ShowerTargetSelection.select(targets.keys.map(\.uuidString),required:required,preferred:preferred)
        } catch ShowerDeviceError.ambiguous {
            guard required == nil else { throw ShowerDeviceError.ambiguous }
            // Same radio name on several controllers: resolve the bound machine id by the read-only
            // identity command (0xAA only, never an authorization, valve or settlement command).
            let ordered = targets.values.sorted {
                let a = signalLevels[$0.identifier] ?? -127, b = signalLevels[$1.identifier] ?? -127
                return a != b ? a > b : $0.identifier.uuidString < $1.identifier.uuidString
            }.map(\.identifier.uuidString)
            return try await ShowerTargetSelection.identify(ordered, machineID:machineID) { [self] candidate in
                guard let uuid = UUID(uuidString:candidate), let device = targets[uuid] else { throw ShowerDeviceError.notFound }
                do {
                    _ = try await establish(device)
                    let frame = try await exchange(ShowerFrames.probeCommand)
                    if ShowerFrames.identity(frame) != machineID.uppercased() { await abandon(device) }
                    return frame
                } catch {
                    await abandon(device)
                    throw error
                }
            }
        }
        guard let uuid = UUID(uuidString:id), let chosen = targets[uuid] else { throw ShowerDeviceError.notFound }
        return try await establish(chosen)
    }
    func exchange(_ data: Data) async throws -> Data {
        if let channelError { throw channelError }
        guard let peripheral, peripheral.state == .connected, let write,
              !decoder.hasPartialFrame, pendingFrame == nil else { throw ShowerDeviceError.disconnected }
        writeAcknowledged = false
        ShowerDiagnosticReport.record("ble.write." + ShowerFrames.command(data).rawValue)
        try await wait("exchange", seconds: 8) { peripheral.writeValue(data, for: write, type: .withResponse) }
        guard let frame = pendingFrame else { throw ShowerDeviceError.malformedFrame }
        ShowerDiagnosticReport.record("ble.reply.\(frame.count)")
        pendingFrame = nil
        return frame
    }
    func disconnect() async {
        ShowerDiagnosticReport.record("ble.disconnect")
        manager?.stopScan()
        complete(.failure(ShowerDeviceError.interrupted))
        if let peripheral {
            peripheral.delegate = nil
            retiring = peripheral
            manager.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil; write = nil; notify = nil
        decoder = ShowerFrameAssembler(); pendingFrame = nil
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if step == "power" {
            if central.state == .poweredOn { complete(.success(())) }
            else if central.state != .unknown && central.state != .resetting { complete(.failure(ShowerDeviceError.bluetoothOff)) }
        } else if central.state != .poweredOn { complete(.failure(ShowerDeviceError.bluetoothOff)) }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        observedIDs.insert(peripheral.identifier)
        if peripheral.name == targetName || advertisementData[CBAdvertisementDataLocalNameKey] as? String == targetName {
            targets[peripheral.identifier] = peripheral
            if RSSI.intValue != 127 { signalLevels[peripheral.identifier] = RSSI.intValue }
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral === self.peripheral, step == "connect" { complete(.success(())) }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral === self.peripheral { complete(.failure(ShowerDeviceError.disconnected)) }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral === retiring, step == "disconnect" { complete(.success(())) }
        else if peripheral === self.peripheral {
            ShowerDiagnosticReport.record("ble.connectionLost." + (step ?? "idle"))
            complete(.failure(ShowerDeviceError.disconnected))
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if step == "service" { complete(error == nil ? .success(()) : .failure(ShowerDeviceError.disconnected)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if step == "characteristics" { complete(error == nil ? .success(()) : .failure(ShowerDeviceError.disconnected)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if step == "subscribe", characteristic === notify {
            complete(error == nil && characteristic.isNotifying ? .success(()) : .failure(ShowerDeviceError.disconnected))
        }
    }
    private func finishExchangeIfReady() {
        if step == "exchange", writeAcknowledged, pendingFrame != nil { complete(.success(())) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard step == "exchange", characteristic === write else { return }
        if error != nil { complete(.failure(ShowerDeviceError.disconnected)); return }
        writeAcknowledged = true
        finishExchangeIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === notify else { return }
        guard error == nil, let value = characteristic.value else {
            channelError = .disconnected
            complete(.failure(ShowerDeviceError.disconnected)); return
        }
        do {
            let frames = try decoder.append(value)
            guard frames.count <= 1, pendingFrame == nil else { throw ShowerDeviceError.malformedFrame }
            if let frame = frames.first { pendingFrame = frame }
            finishExchangeIfReady()
        } catch {
            channelError = .malformedFrame
            complete(.failure(ShowerDeviceError.malformedFrame))
        }
    }
}
