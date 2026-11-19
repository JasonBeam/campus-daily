import Foundation

/// UserDefaults that keep everything in memory: the sample's preferences and its `@AppStorage`.
/// Nothing is read from or written to any preferences file; values registered with
/// `register(defaults:)` are seen as usual. Gone with the instance.
public final class SampleDefaults: UserDefaults {
    // `values` and `registered` are touched only under `lock`.
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var registered: [String: Any] = [:]

    public init() {
        // A suite nothing writes to: no call below reaches super's storage.
        super.init(suiteName: "sample.memory.\(UUID().uuidString)")!
    }

    public override func object(forKey key: String) -> Any? {
        lock.withLock { values[key] ?? registered[key] }
    }

    public override func set(_ value: Any?, forKey key: String) {
        willChangeValue(forKey: key)
        lock.withLock { values[key] = value }
        didChangeValue(forKey: key)
    }

    public override func removeObject(forKey key: String) { set(nil, forKey: key) }

    public override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock { registered.merge(registrationDictionary) { $1 } }
    }

    public override func removePersistentDomain(forName domainName: String) {
        lock.withLock { values.removeAll() }
    }

    public override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { registered.merging(values) { $1 } }
    }

    public override func set(_ value: Int, forKey key: String) { set(value as Any?, forKey: key) }
    public override func set(_ value: Float, forKey key: String) { set(value as Any?, forKey: key) }
    public override func set(_ value: Double, forKey key: String) { set(value as Any?, forKey: key) }
    public override func set(_ value: Bool, forKey key: String) { set(value as Any?, forKey: key) }
    public override func set(_ url: URL?, forKey key: String) { set(url as Any?, forKey: key) }

    public override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    public override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    public override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    public override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    public override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    public override func url(forKey key: String) -> URL? { object(forKey: key) as? URL }
    public override func integer(forKey key: String) -> Int { number(key)?.intValue ?? 0 }
    public override func float(forKey key: String) -> Float { number(key)?.floatValue ?? 0 }
    public override func double(forKey key: String) -> Double { number(key)?.doubleValue ?? 0 }
    public override func bool(forKey key: String) -> Bool {
        if let text = object(forKey: key) as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return number(key)?.boolValue ?? false
    }

    private func number(_ key: String) -> NSNumber? {
        switch object(forKey: key) {
        case let n as NSNumber: return n
        case let s as String: return Double(s).map { NSNumber(value: $0) }
        default: return nil
        }
    }
}
