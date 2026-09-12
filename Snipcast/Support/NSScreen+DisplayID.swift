import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }
}
