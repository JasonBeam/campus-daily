import Foundation
import SwiftUI
import UIKit
import Core

/// Hot-water diagnostics: event names and times only (no ids, frames or tokens), kept on this phone.
/// The export also carries the school credential-lifetime lines (kind and minutes only), kept
/// apart in `CredentialLifetimeLog` so they don't use up the 300 hot-water lines.
@MainActor enum ShowerDiagnosticReport {
    struct Entry: Codable { let at: Date; let event: String }
    private static let limit = 300
    private static var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Water", isDirectory: true).appendingPathComponent("diagnostics.json")
    }
    private static var entries: [Entry] = (try? Data(contentsOf: logURL)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []

    static func record(_ event: String) {
        entries.append(Entry(at: Date(), event: String(event.prefix(80))))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        let folder = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: logURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var excluded = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    struct Empty: Error {}

    /// Where `export` puts the shared report (deleted by reset).
    static var exportFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WaterDiagnostics", isDirectory: true)
    }

    /// Reset: forget the events held in memory too, or the next one would write them all back.
    static func clearMemory() { entries = [] }

    static func export(phase: ShowerPhase, needsReview: Bool, manualSettleAttempts: Int) throws -> URL {
        let lifetimes = CredentialLifetimeLog(store:AppEnvironment.store).entries()
        guard !entries.isEmpty || !lifetimes.isEmpty else { throw Empty() }
        struct Report: Encodable {
            let schema = 3
            let generatedAt = Date()
            let appVersion: String
            let build: String
            let deviceModel: String
            let systemVersion: String
            let phase: ShowerPhase
            let needsReview: Bool
            let manualSettleAttempts: Int
            let events: [Entry]
            let credentialLifetime: [CredentialLifetimeLog.Entry]
        }
        var hardware = utsname(); uname(&hardware)
        let model = withUnsafeBytes(of: &hardware.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let report = Report(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                            deviceModel: model, systemVersion: UIDevice.current.systemVersion,
                            phase: phase, needsReview: needsReview, manualSettleAttempts: manualSettleAttempts, events: entries,
                            credentialLifetime: lifetimes)
        let folder = exportFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("XiaoRiChang-water-diagnostics.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return file
    }
}

struct ShowerDiagnosticShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
