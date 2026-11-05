import Foundation

/// The product copy for a shower that is over without a settlement in the app (stopped on the
/// controller, or an outcome the app doesn't know): the school settles it. The one place these
/// strings are written (`ShowerRetiredWordsTests` checks it).
public enum ShowerAuthorText {
    /// The stopped page's headline.
    public static let stoppedTitle = "上一次洗好了"
    /// The one line under its button, the same for one or many such showers (no count).
    public static let stoppedNote = "在水控上按停就算洗完了，学校会自己扣费，可以在学校的热水记录里看。"
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
    public static let keptStatus = "上一次洗好了，学校会自己扣费。"
    /// 开始洗澡 from Siri or Shortcuts over it found the controller in use: nothing was sent.
    public static let spokenInUse = "水控有人在用，这次没开水，也没扣钱。如果是你没停的水，先在水控上按停再试。"
}
