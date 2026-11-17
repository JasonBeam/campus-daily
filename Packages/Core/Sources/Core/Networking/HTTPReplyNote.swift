import Foundation

/// What kind of refusal a reply was, for the request log: one fixed word, never the server's or
/// the page's words (they can hold ids, names or what was typed). Only the requests that ask
/// for it (`HTTPRequest.replyNote`) get one.
public enum HTTPReplyNote: String, Sendable, CaseIterable {
    /// The CAS password POST came back as a page (200 or 401): no error on it, wrong-password
    /// wording, a lock/captcha/check in force, something else in the way (a lock to come, SMS
    /// login), a bare 认证失败/登录失败, or an error none of those.
    case casNoError, casWrong, casBlocked, casSoftBlocked, casVagueWrong, casUnrecognised
    /// An lxt6/ecykt envelope with a non-zero code: no message, one about the balance, any other.
    case msgEmpty, msgBalance, msgOther

    /// Words in a refusal that mean the balance.
    public static let balanceWords = ["余额不足", "欠费", "充值"]

    /// The kind of message beside a non-zero envelope code (`code`/`Code`, `msg`/`message`/
    /// `Message`, the envelope also as a JSON string); nil for code 0 or no envelope.
    public static func envelope(_ body: Data) -> HTTPReplyNote? {
        guard !body.isEmpty, body.count <= 1024 * 1024, var json = try? JSONValue.parse(body) else { return nil }
        if case .string(let s) = json, let inner = try? JSONValue.parse(s) { json = inner }
        guard json.object != nil, let code = ResponseDecoding.code(json), code != "0" else { return nil }
        let message = ResponseDecoding.message(json).trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty { return .msgEmpty }
        return balanceWords.contains { message.contains($0) } ? .msgBalance : .msgOther
    }
}
