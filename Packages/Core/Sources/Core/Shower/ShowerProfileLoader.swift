import Foundation

/// `.waterconfig` import (and the bundled profile staged by `Scripts/stage-water-profile.py`):
/// exactly `{secret, sid, bleName, typeID, version}`. Any other key is refused so a file can
/// never silently carry another student's account, room or controller. Same file on iOS and Android.
public enum ShowerConfigFile {
    public static let maxBytes = 8192
    public static let keys: Set<String> = ["secret", "sid", "bleName", "typeID", "version"]

    public static func parse(_ data: Data, source: ShowerProfileSource) throws -> ShowerPlatformProfile {
        guard data.count <= maxBytes, let root = try? JSONValue.parse(data), let o = root.object else {
            throw ShowerProfileError.unreadable(source)
        }
        guard Set(o.keys) == keys else { throw ShowerProfileError.unreadable(source) }
        guard case .string(let secret)? = o["secret"], case .string(let sid)? = o["sid"], case .string(let ble)? = o["bleName"],
              case .int(let typeID)? = o["typeID"], case .int(let version)? = o["version"] else {
            throw ShowerProfileError.unreadable(source)
        }
        func ok(_ s: String, _ max: Int) -> Bool {
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.utf8.count <= max
                && s.rangeOfCharacter(from: .controlCharacters) == nil
        }
        guard ok(secret, 256), ok(sid, 128), ok(ble, 64),
              (0...Int64(Int32.max)).contains(typeID), (1...Int64(Int32.max)).contains(version) else {
            throw ShowerProfileError.incomplete(source)
        }
        return ShowerPlatformProfile(secret: secret, sid: sid, bleName: ble, typeId: String(typeID), version: String(version))
    }
}

/// Resolves the two profile sources (`ShowerProfileSource`). File and bundle reads are
/// injected (App: `Bundle.main` / the imported-file container).
public struct ShowerProfileLoader: ShowerProfileProviding {
    let bundled: @Sendable () throws -> Data?
    let imported: @Sendable (String) throws -> Data?

    public init(bundled: @escaping @Sendable () throws -> Data?, imported: @escaping @Sendable (String) throws -> Data?) {
        self.bundled = bundled; self.imported = imported
    }

    public func resolve(_ source: ShowerProfileSource) async throws -> ShowerPlatformAccess {
        switch source {
        case .bundled:
            guard let data = try read(bundled, source) else { throw ShowerProfileError.missing(source) }
            return .local(try ShowerConfigFile.parse(data, source: source), source: source)
        case .imported(let name):
            guard let data = try read({ try imported(name) }, source) else { throw ShowerProfileError.missing(source) }
            return .local(try ShowerConfigFile.parse(data, source: source), source: source)
        }
    }

    private func read(_ load: () throws -> Data?, _ source: ShowerProfileSource) throws -> Data? {
        do { return try load() } catch { throw ShowerProfileError.unreadable(source) }
    }
}
