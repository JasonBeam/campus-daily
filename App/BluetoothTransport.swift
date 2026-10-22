import Foundation
@preconcurrency import CoreBluetooth
import WaterCore

// CoreBluetooth delegates are delivered on the explicit main queue below.
@MainActor final class BluetoothTransport: NSObject, WaterTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var retiring: CBPeripheral?
    private var targets: [UUID: CBPeripheral] = [:]
    private var targetName = ""
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
    func connect(config: WaterConfig, expectedPeripheral: String?) async throws -> String {
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
        targets.removeAll()
        // Some water controllers omit FFE0 from advertising, so inspect names first.
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        do { try await Task.sleep(for: .seconds(6)) }
        catch { manager.stopScan(); throw WaterError.interrupted }
        manager.stopScan()
        let matches = targets.values.filter { expectedPeripheral == nil || $0.identifier.uuidString == expectedPeripheral }
        guard matches.count == 1, let chosen = matches.first else { throw WaterError.targetNotFound }
        peripheral = chosen
        chosen.delegate = self
        try await wait("connect") { manager.connect(chosen) }
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
    func exchange(_ data: Data) async throws -> Data {
        if let channelError { throw channelError }
        guard let peripheral, peripheral.state == .connected, let write,
              !decoder.hasPartialFrame, pendingFrame == nil else { throw WaterError.bluetooth }
        writeAcknowledged = false
        try await wait("exchange", seconds: 8) { peripheral.writeValue(data, for: write, type: .withResponse) }
        guard let frame = pendingFrame else { throw WaterError.malformedFrame }
        pendingFrame = nil
        return frame
    }
    func disconnect() {
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
        if peripheral.name == targetName || advertisementData[CBAdvertisementDataLocalNameKey] as? String == targetName {
            targets[peripheral.identifier] = peripheral
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
        else if peripheral === self.peripheral { complete(.failure(WaterError.bluetooth)) }
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
