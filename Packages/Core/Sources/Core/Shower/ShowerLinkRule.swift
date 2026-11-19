import Foundation

/// Starting a shower and the read-only controller check (核对宿舍的水控) share the one Bluetooth
/// link, and the check disconnects when it ends: a start beside it could lose the writes after
/// its authorization and leave a record to check. So one waits for the other, whichever way
/// round (the page, a Shortcut or the Live Activity alike).
public enum ShowerLinkRule {
    /// 开始洗澡: `ready` = everything outside the link allows it (a binding, the profile, an
    /// engine, storage). Not while other controller work or a check runs.
    public static func mayStart(_ state: ShowerState, ready: Bool, busy: Bool, inspecting: Bool) -> Bool {
        ready && !busy && !inspecting && state.canStart
    }

    /// The controller check: not while a start, an end or another check runs, and not while a
    /// session could still be open or charged.
    public static func mayInspect(_ state: ShowerState, busy: Bool, inspecting: Bool) -> Bool {
        !busy && !inspecting && state.canStart
    }
}
