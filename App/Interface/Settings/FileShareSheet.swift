import UIKit

/// The system share sheet for one file, straight from a tap, over whatever is on screen (高级 can
/// sit inside the settings sheet). `closed` runs once the share sheet is gone, shared or not.
@MainActor
enum FileShareSheet {
    /// False: there was nothing to present from, and `closed` will not run.
    static func present(_ file: URL, closed: @escaping @MainActor () -> Void) -> Bool {
        guard let top = topViewController() else { return false }
        let sheet = UIActivityViewController(activityItems:[file], applicationActivities:nil)
        sheet.completionWithItemsHandler = { [weak sheet] _, _, _, _ in
            MainActor.assumeIsolated {
                // Back from an activity that was cancelled, the sheet can still be up: keep the file.
                if let sheet, sheet.presentingViewController != nil, !sheet.isBeingDismissed { return }
                closed()
            }
        }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x:top.view.bounds.midX, y:top.view.bounds.midY, width:0, height:0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated:true)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}
