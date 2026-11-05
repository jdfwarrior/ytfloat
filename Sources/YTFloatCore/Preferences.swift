import Foundation

public final class Preferences {
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["alwaysOnTop": true, "opacity": 1.0, "autoplay": true,
            "lockAspect": true, "showControls": true, "overlayTimeout": 3.0, "allSpaces": true])
    }
    public var alwaysOnTop: Bool { get { defaults.bool(forKey: "alwaysOnTop") } set { defaults.set(newValue, forKey: "alwaysOnTop") } }
    public var opacity: Double {
        get { let n = defaults.double(forKey: "opacity"); return n.isFinite ? min(1, max(0.35, n)) : 1 }
        set { defaults.set(newValue.isFinite ? min(1, max(0.35, newValue)) : 1, forKey: "opacity") }
    }
    public var autoplay: Bool { get { defaults.bool(forKey: "autoplay") } set { defaults.set(newValue, forKey: "autoplay") } }
    public var lockAspect: Bool { get { defaults.bool(forKey: "lockAspect") } set { defaults.set(newValue, forKey: "lockAspect") } }
    public var showControls: Bool { get { defaults.bool(forKey: "showControls") } set { defaults.set(newValue, forKey: "showControls") } }
    public var allSpaces: Bool { get { defaults.bool(forKey: "allSpaces") } set { defaults.set(newValue, forKey: "allSpaces") } }
    public var overlayTimeout: Double {
        get { let n = defaults.double(forKey: "overlayTimeout"); return [2.0, 3.0, 5.0].contains(n) ? n : 3 }
        set { defaults.set([2.0, 3.0, 5.0].contains(newValue) ? newValue : 3, forKey: "overlayTimeout") }
    }
}
