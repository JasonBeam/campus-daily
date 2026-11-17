import Foundation

/// The product copy for a shower that is over without a settlement in the app (stopped on the
/// controller, or an outcome the app doesn't know): the school settles it. The one place these
/// strings are written (`ShowerRetiredWordsTests` checks it).
public enum ShowerAuthorText {
    /// The stopped page's headline.
    public static let stoppedTitle = "上一次洗好了"
    /// The one line under its button, the same for one or many such showers (no count).
    public static let stoppedNote = "在水控上按停就算洗完了。费用看校园卡记录，扣费要 1 小时左右才出现。"
    /// The stopped page's one button (only there).
    public static let startNext = "开始下一次洗澡"
    /// Home's button and 清爽's 热水 tile over it: they open the timer page.
    public static let homeButton = "去洗澡"
    /// What VoiceOver reads for that button.
    public static let homeButtonLabel = "去洗澡，上一次洗好了"
    /// What Siri, Shortcuts and the record's status say after it.
    /// An authorize the school answered unclearly: nothing ran (Siri and Shortcuts).
    public static let spokenNoWater = "水没开。" + spokenRetry
    /// Its tail, also after the school's own sentence.
    public static let spokenRetry = "打开校日常再试一次。"
    /// The status of a shower that is over (the lock screen, Siri when a start can't go).
    public static let keptStatus = "上一次洗好了。费用看校园卡记录，扣费要 1 小时左右才出现。"
    /// The stopped page over a close the controller answered busy (暖橙): its headline and line.
    public static let closeBusyTitle = "水控还没停"
    public static let closeBusyBody = "结束发出去了，水控还在出水。在水控上按停就行，费用看校园卡记录，扣费要 1 小时左右才出现。"
    /// A check over an unconfirmed or busy close found water running (暖橙): nothing more was sent.
    public static let closeStillRunning = "水控还在出水，这次没再发结束，免得关掉别人的水。是你的水的话，在水控上按停。"
    /// The status of a close the controller answered busy (the lock screen, Siri, the record).
    public static let closeBusyStatus = "水控还没停，在水控上按停。费用看校园卡记录，扣费要 1 小时左右才出现。"
    /// 开始洗澡 from Siri or Shortcuts over it found the controller in use: nothing was sent.
    public static let spokenInUse = "水控有人在用，这次没开水，也没扣钱。如果是你没停的水，先在水控上按停再试。"
}
