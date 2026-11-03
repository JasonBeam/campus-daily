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

/// The profile the app uses: the imported `.waterconfig` when it reads as one, else the one
/// staged into the bundle. Both go through `ShowerConfigFile.parse`. Reads are injected (App:
/// the imported-file container / `Bundle.main`).
public enum ShowerProfileLoader {
    public static func localProfile(imported: () throws -> Data?, bundled: () throws -> Data?) -> ShowerPlatformProfile? {
        if let data = try? imported(), let profile = try? ShowerConfigFile.parse(data, source: .imported(fileName: importedFileName)) {
            return profile
        }
        if let data = try? bundled(), let profile = try? ShowerConfigFile.parse(data, source: .bundled) { return profile }
        return nil
    }

    public static let importedFileName = "imported.waterconfig"
}
