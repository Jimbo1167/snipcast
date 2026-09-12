import AppKit

@MainActor
enum ShareService {
    /// Hands the file to Messages as a new attachment. Returns false if Messages is unavailable.
    @discardableResult
    static func sendWithMessages(_ url: URL) -> Bool {
        guard let service = NSSharingService(named: .composeMessage),
              service.canPerform(withItems: [url]) else { return false }
        service.perform(withItems: [url])
        return true
    }

    static func copyToPasteboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
