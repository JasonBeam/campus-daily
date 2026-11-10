import Foundation

/// 清爽's 热水洗澡 page: a short headline and one plain line for each face, the button's words
/// and the footnote under it. A problem of any kind reads 「本次待核对」 with its reason under it.
public enum ClearShowerText {
    public static let readyTitle = "准备洗澡"
    public static let readyBody = "准备好了，靠近水控即可开始"
    /// Starting and ending: the headline and the button while they run.
    public static let busyTitle = "正在处理"
    public static let busyButton = "正在处理…"
    public static let startingBody = "正在连接并申请授权…"
    public static let endingBody = "正在结束并结算…"
    public static let runningTitle = "热水已授权"
    public static let runningBody = "已授权，请按设备出水键"
    public static let doneTitle = "结算完成"
    public static let doneBody = "服务器已确认结算"
    public static let problemTitle = "本次待核对"
    public static let connectFailedBody = "蓝牙连接失败，请靠近水控并退出其他水控连接页面"
    public static let inUseBody = "水控仍在忙，已断开连接；确认停水后请稍后再试"
    public static let deniedBody = "学校未授权本次用水，未扣费；请稍后再试"
    public static let stoppedBody = "水控未保留本次授权，结算尚未确认；请核对官方用水记录"

    public static let start = "开始洗澡"
    public static let end = "结束并结算"
    /// Under 开始洗澡 (and while it runs).
    public static let startNote = "授权后，按水控上的出水键。"
    /// Under 结束并结算 from the start of the water until the settlement is done.
    public static let endNote = "结算完成前，请留在水控附近。"
    /// Under the button of a shower that is over.
    public static let nextNote = "上一笔费用继续保留；确认机身已停水后，可重新检查并开始。"

    public static let cost = "本次费用"
    public static let costLater = "结算后显示"
    public static let costMissing = "金额未返回"
    public static let lastUse = "最近一次用水"
    public static let lastUseSettled = "已结算"

    /// The folded controller check.
    public static let connection = "连接检查与设备信息"
    public static let inspect = "扫描并核对本宿舍水控"
    public static let inspecting = "正在核对…"
    public static let verified = "已识别的宿舍设备"
    public static let deviceName = "设备名称"
    public static let machine = "水控编号"
    public static let signal = "本次信号"
    public static func deviceID(_ prefix: String) -> String { "设备标识 " + prefix + "…" }
    public static func nearby(_ count: Int) -> String { "发现 \(count) 台同名设备，已按宿舍水控编号匹配。" }
    public static func verifiedAt(_ time: String) -> String { "核对于 " + time }
    public static let disconnected = "核对后已断开；开始洗澡时再连接。"
    public static let readOnly = "只读取设备编号，不会出水。"

    /// A face's headline and the line under it. `phase` nil: no session shown (ready).
    /// `inUse`: refused because the controller is in use (or found so before the next shower).
    public static func face(_ phase: ShowerPagePhase?, inUse: Bool = false) -> (title: String, body: String, problem: Bool) {
        switch phase {
        case nil: return (readyTitle, readyBody, false)
        case .connecting?: return (busyTitle, startingBody, false)
        case .running?: return (runningTitle, runningBody, false)
        case .settling?: return (busyTitle, endingBody, false)
        case .done?: return (doneTitle, doneBody, false)
        case .connectFailed?: return (problemTitle, connectFailedBody, true)
        case .denied?: return (problemTitle, inUse ? inUseBody : deniedBody, true)
        case .stopped?: return (problemTitle, inUse ? inUseBody : stoppedBody, true)
        }
    }

    /// The button of an answered face: settled, 开始洗澡, which only brings back the ready face
    /// (starting takes a second tap there); refused, 好, which closes the page.
    public static func answerButton(_ phase: ShowerPagePhase) -> (title: String, leavesPage: Bool) {
        phase == .done ? (start, false) : ("好", true)
    }

    /// The footnote under the page's button.
    public static func note(_ phase: ShowerPagePhase?) -> String? {
        switch phase {
        case nil, .connecting?, .connectFailed?: return startNote
        case .running?, .settling?: return endNote
        case .stopped?: return nextNote
        case .done?, .denied?: return nil
        }
    }
}
