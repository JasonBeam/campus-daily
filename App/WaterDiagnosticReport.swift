import Foundation
import SwiftUI
import UIKit
import WaterCore

@MainActor enum WaterDiagnosticReport {
    private static var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WaterSession", isDirectory: true).appendingPathComponent("diagnostics-v1.json")
    }
    static let trace: WaterDiagnostics = {
        let entries = (try? Data(contentsOf: logURL)).flatMap { try? JSONDecoder().decode([WaterDiagnostics.Entry].self, from: $0) } ?? []
        return WaterDiagnostics(entries: entries) { entries in
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: logURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            var folder = logURL.deletingLastPathComponent()
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
    }()
    static func export(stage: SessionStage?, needsReview: Bool) throws -> URL {
        struct Report: Encodable {
            let schema = 1
            let generatedAt = Date()
            let appVersion: String
            let build: String
            let deviceModel: String
            let systemVersion: String
            let sessionStage: SessionStage?
            let stateReviewRequired: Bool
            let events: [WaterDiagnostics.Entry]
        }
        var hardware = utsname(); uname(&hardware)
        let model = withUnsafeBytes(of: &hardware.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let report = Report(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                            deviceModel: model, systemVersion: UIDevice.current.systemVersion,
                            sessionStage: stage, stateReviewRequired: needsReview, events: trace.entries)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WaterDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("CampusDaily-water-diagnostics.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return file
    }
}

struct WaterDiagnosticShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
