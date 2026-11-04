import Foundation

/// Private, bounded RX capture in explicitly built diagnostic candidates only.
/// Deliberately excluded from the shareable, redacted diagnostic report.
@MainActor enum WaterPassiveCapture {
    #if WATER_PASSIVE_DIAGNOSTICS
    static func export() throws -> URL {
        let source = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("WaterSession/passive-bluetooth-v1.json")
        let bytes = try Data(contentsOf:source)
        guard bytes.count <= 65536 else { throw CocoaError(.fileReadCorruptFile) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WaterDiagnostics",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let destination = folder.appendingPathComponent("CampusDaily-water-passive-private.json")
        try bytes.write(to:destination,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        return destination
    }
    #endif
    static func receive(_ bytes: Data, awaitingReply: Bool) {
        #if WATER_PASSIVE_DIAGNOSTICS
        guard !bytes.isEmpty, bytes.count <= 256 else { return }
        struct Entry: Codable {
            let receivedAt: Date
            let awaitingReply: Bool
            let bytes: Data
        }
        do {
            var folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
                .appendingPathComponent("WaterSession",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,
                attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let file = folder.appendingPathComponent("passive-bluetooth-v1.json")
            let saved = try? Data(contentsOf:file)
            var history = saved.flatMap { $0.count <= 65536 ? try? JSONDecoder().decode([Entry].self,from:$0) : nil } ?? []
            history.append(Entry(receivedAt:Date(),awaitingReply:awaitingReply,bytes:bytes))
            try JSONEncoder().encode(Array(history.suffix(64))).write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Capturing must never change the outcome of a water operation. */ }
        #endif
    }
}
