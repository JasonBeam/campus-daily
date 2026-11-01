import Foundation

/// The widget's links (campusdaily://home, ://login, ://settings/account) close whatever page is
/// open. Any app can open them, so while a payment may be under way they are ignored: on a
/// top-up page (paid inside the school's web page) or on the laundry page with an order between
/// creation and the end of the payment check. Returning from Alipay must find that page still there.
public enum WidgetLink {
    public static func mayClosePages(rechargeOpen: Bool, laundryOpen: Bool, laundry: LaundryPhase?) -> Bool {
        if rechargeOpen { return false }
        guard laundryOpen, let laundry else { return true }
        switch laundry {
        case .creating, .reconcile, .created, .paying, .verifying: return false
        case .none, .active, .cancelling, .attention: return true
        }
    }
}
