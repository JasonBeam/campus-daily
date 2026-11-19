import Foundation

/// Key/value preferences (UserDefaults in the app, a dictionary in tests).
public protocol PreferenceStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStorage {}
