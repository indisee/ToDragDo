import Foundation

public enum DeviceID {
    private static let key = "todragdo.deviceId"

    public static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }
}
