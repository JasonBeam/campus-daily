import Foundation
import WaterCore

// Explicit read-only school queries. No water-provider or Bluetooth operations.
@main struct CampusReadCheck {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 3 else { throw CampusError.configuration }
            let config = try JSONDecoder().decode(CampusConfig.self,
                from: Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
            try config.validate()
            let provider = CampusProvider()
            var snapshot = CampusSnapshot(owner:config.cacheIdentity)
            do { snapshot.recordBalance(.success(try await provider.balance(config:config))) }
            catch { snapshot.recordBalance(.failure((error as? CampusError) ?? .network)) }
            do { snapshot.recordRoom(.success(try await provider.room(config:config))) }
            catch { snapshot.recordRoom(.failure((error as? CampusError) ?? .network)) }
            let url = URL(fileURLWithPath:CommandLine.arguments[2])
            try JSONEncoder().encode(snapshot).write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            print("Card balance confirmed: \(snapshot.balance != nil). Dorm configured: \(snapshot.room != nil).")
            if let error = snapshot.cardError { print(error.rawValue) }
            print("Water authorization/settlement requests: 0. Bluetooth writes: 0.")
        } catch {
            fputs("Read-only campus check failed; private values were not printed.\n",stderr)
            exit(1)
        }
    }
}
