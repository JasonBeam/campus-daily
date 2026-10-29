import Foundation
@preconcurrency import CoreBluetooth
import WaterCore

struct WaterDeviceCandidate: Identifiable {
    let id: String
    let name: String
    let rssi: Int?
}

struct VerifiedWaterDevice {
    let id: String
    let name: String
    let machineID: String
    let rssi: Int?
    let nearbyCount: Int
    let verifiedAt: Date
}

// CoreBluetooth delegates are delivered on the explicit main queue below.
@MainActor final class BluetoothTransport: NSObject, WaterTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var retiring: CBPeripheral?
    private var targets: [UUID: CBPeripheral] = [:]
    var targetPicker: (([WaterDeviceCandidate]) async throws -> String)?
    private var signalLevels: [UUID: Int] = [:]
    private var targetName = ""
    private var observedIDs = Set<UUID>()
    private var notify: CBCharacteristic?
    private var write: CBCharacteristic?
    private var decoder = FrameDecoder()
    private var pendingFrame: Data?
    private var channelError: WaterError?
    private var writeAcknowledged = false
    private var step: String?
    private var waiter: CheckedContinuation<Void, Error>?
    private var timer: Task<Void, Never>?

    private func wait(_ name: String, seconds: Double = 15, begin: () -> Void) async throws {
        try Task.checkCancellation()
        guard waiter == nil else { throw WaterError.busy }
        WaterDiagnosticReport.trace.record(.bluetoothStep, step: WaterDiagnostics.Step(rawValue: name))
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                step = name
                waiter = continuation
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.complete(.failure(WaterError.timedOut))
                }
                begin()
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.complete(.failure(WaterError.interrupted)) } })
    }
    private func complete(_ result: Result<Void, Error>) {
        let continuation = waiter
        waiter = nil; step = nil
        timer?.cancel(); timer = nil
        continuation?.resume(with: result)
    }
    private func prepare(config: WaterConfig) async throws {
        if manager == nil { manager = CBCentralManager(delegate: self, queue: .main) }
        if manager.state == .unknown || manager.state == .resetting {
            try await wait("power") {}
        }
        guard manager.state == .poweredOn else { throw WaterError.bluetoothOff }
        if let old = retiring, old.state != .disconnected {
            try await wait("disconnect") { manager.cancelPeripheralConnection(old) }
        }
        retiring = nil
        targetName = config.bleName
    }
    private func scanTargets() async throws {
        targets.removeAll(); observedIDs.removeAll(); signalLevels.removeAll()
        // Some water controllers omit FFE0 from advertising, so inspect names first.
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        do { try await Task.sleep(for: .seconds(12)) }
        catch { manager.stopScan(); throw WaterError.interrupted }
        manager.stopScan()
    }
    private func scan(config: WaterConfig) async throws {
        try await prepare(config:config)
        try await scanTargets()
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
        try await wait("service") { chosen.discoverServices([CBUUID(string: WaterProtocol.service)]) }
        guard let service = chosen.services?.first(where: { $0.uuid == CBUUID(string: WaterProtocol.service) }) else {
            throw WaterError.bluetooth
        }
        try await wait("characteristics") {
            chosen.discoverCharacteristics([CBUUID(string: WaterProtocol.notify), CBUUID(string: WaterProtocol.write)], for: service)
        }
        notify = service.characteristics?.first { $0.uuid == CBUUID(string: WaterProtocol.notify) }
        write = service.characteristics?.first { $0.uuid == CBUUID(string: WaterProtocol.write) }
        guard let notify, let write, notify.properties.contains(.notify), write.properties.contains(.write) else {
            throw WaterError.bluetooth
        }
        decoder = FrameDecoder(); pendingFrame = nil; channelError = nil
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
    func verifiedInformation(id: String, machineID: String) -> VerifiedWaterDevice {
        VerifiedWaterDevice(id:id,name:targetName,machineID:machineID.uppercased(),rssi:UUID(uuidString:id).flatMap { signalLevels[$0] },nearbyCount:targets.count,verifiedAt:Date())
    }
    func inspect(config: WaterConfig, remembered: String?) async throws -> String {
        try await scan(config:config)
        recordScan(remembered:remembered)
        if targets.isEmpty { return WaterError.targetMissing.rawValue }
        if let remembered, targets.keys.contains(where: { $0.uuidString == remembered }) {
            return "发现 \(targets.count) 个同名水控，已识别上次使用的设备"
        }
        return targets.count == 1 ? "发现 1 个目标候选，开始时会核对水控编号" : WaterError.targetAmbiguous.rawValue
    }
    func connect(config: WaterConfig, expectedPeripheral: String?, preferredPeripheral: String?) async throws -> String {
        try await prepare(config:config)
        let remembered = expectedPeripheral ?? preferredPeripheral
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
                // rescan and keep the existing exact/preferred-device selection rules.
            }
        }
        try await scanTargets()
        recordScan(remembered:remembered)
        let id: String
        do {
            id = try WaterTargetSelection.select(targets.keys.map(\.uuidString),required:expectedPeripheral,preferred:preferredPeripheral)
        } catch WaterError.targetAmbiguous {
            guard expectedPeripheral == nil else { throw WaterError.targetAmbiguous }
            let candidates = targets.values.map {
                WaterDeviceCandidate(id:$0.identifier.uuidString,name:targetName,rssi:signalLevels[$0.identifier])
            }.sorted {
                if $0.rssi != $1.rssi { return ($0.rssi ?? -127) > ($1.rssi ?? -127) }
                return $0.id < $1.id
            }
            // Resolve the configured hardware ID, not the shared BT19-S radio name.
            // This sends only 0xAA, never an authorization, valve or settlement command.
            do {
                let matched = try await WaterIdentitySelection.match(candidates.map(\.id),machineID:config.machineID) { [self] candidate in
                    guard let uuid = UUID(uuidString:candidate), let device = targets[uuid] else { throw WaterError.targetMissing }
                    do {
                        _ = try await establish(device)
                        let frame = try await exchange(Data([0xAA]))
                        if (try? WaterProtocol.identity(frame)) != config.machineID.uppercased() { await abandon(device) }
                        return frame
                    } catch {
                        await abandon(device)
                        throw error
                    }
                }
                return matched
            } catch WaterError.targetMissing {
                // Keep manual selection only when read-only identification could not resolve a target.
            }
            guard let targetPicker else { throw WaterError.targetMissing }
            let selected = try await targetPicker(candidates)
            try Task.checkCancellation()
            id = try WaterTargetSelection.select(targets.keys.map(\.uuidString),required:selected,preferred:nil)
        }
        guard let uuid = UUID(uuidString:id), let chosen = targets[uuid] else { throw WaterError.targetMissing }
        return try await establish(chosen)
    }
    func exchange(_ data: Data) async throws -> Data {
        if let channelError { throw channelError }
        guard let peripheral, peripheral.state == .connected, let write,
              !decoder.hasPartialFrame, pendingFrame == nil else { throw WaterError.bluetooth }
        writeAcknowledged = false
        let command: WaterDiagnostics.Command = data == Data([0xAA]) ? .identity : data.count == 15 ? .authorization : data.count == 5 && data.first == 0xAC ? .close : .other
        WaterDiagnosticReport.trace.record(.bluetoothWrite, command: command)
        try await wait("exchange", seconds: 8) { peripheral.writeValue(data, for: write, type: .withResponse) }
        guard let frame = pendingFrame else { throw WaterError.malformedFrame }
        WaterDiagnosticReport.trace.record(.bluetoothReply, frame: frame)
        pendingFrame = nil
        return frame
    }
    func disconnect() {
        WaterDiagnosticReport.trace.record(.disconnected)
        manager?.stopScan()
        complete(.failure(WaterError.interrupted))
        if let peripheral {
            peripheral.delegate = nil
            retiring = peripheral
            manager.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil; write = nil; notify = nil
        decoder = FrameDecoder(); pendingFrame = nil
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if step == "power" {
            if central.state == .poweredOn { complete(.success(())) }
            else if central.state != .unknown && central.state != .resetting { complete(.failure(WaterError.bluetoothOff)) }
        } else if central.state != .poweredOn { complete(.failure(WaterError.bluetoothOff)) }
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
        if peripheral === self.peripheral { complete(.failure(WaterError.bluetooth)) }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral === retiring, step == "disconnect" { complete(.success(())) }
        else if peripheral === self.peripheral {
            WaterDiagnosticReport.trace.record(.connectionLost, step: step.flatMap(WaterDiagnostics.Step.init(rawValue:)), error: .bluetooth)
            complete(.failure(WaterError.bluetooth))
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if step == "service" { complete(error == nil ? .success(()) : .failure(WaterError.bluetooth)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if step == "characteristics" { complete(error == nil ? .success(()) : .failure(WaterError.bluetooth)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if step == "subscribe", characteristic === notify {
            complete(error == nil && characteristic.isNotifying ? .success(()) : .failure(WaterError.bluetooth))
        }
    }
    private func finishExchangeIfReady() {
        if step == "exchange", writeAcknowledged, pendingFrame != nil { complete(.success(())) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard step == "exchange", characteristic === write else { return }
        if error != nil { complete(.failure(WaterError.bluetooth)); return }
        writeAcknowledged = true
        finishExchangeIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === notify else { return }
        guard error == nil, let value = characteristic.value else {
            channelError = .bluetooth
            complete(.failure(WaterError.bluetooth)); return
        }
        do {
            let frames = try decoder.append(value)
            guard frames.count <= 1, pendingFrame == nil else { throw WaterError.malformedFrame }
            if let frame = frames.first { pendingFrame = frame }
            finishExchangeIfReady()
        } catch {
            channelError = .malformedFrame
            complete(.failure(WaterError.malformedFrame))
        }
    }
}
