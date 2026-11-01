import Foundation

/// Everything the App's WKWebView needs to open a school recharge page already signed in.
public struct RechargeWebSession: Sendable, Equatable, CustomStringConvertible {
    public var kind: RechargeKind
    /// Card: `/ykt-view/recharge?isbind=1`. Electricity: `getPowerUrl?…` (the WebView follows its 302).
    public var startURL: URL
    /// `localStorage.elecampus_state` JSON. Holds the fresh token: never log it.
    public var stateJSON: String
    /// Document-start user script; only acts on the ecykt origin.
    public var userScript: String
    public var userAgent: String

    public var description: String { "RechargeWebSession(\(kind.rawValue), <redacted>)" }
}

public enum RechargeWebSessionBuilder {
    /// Builds `elecampus_state` like the official CSA login does, but with the **fresh**
    /// `loginBySysId` token in `logintoken` (not the stored one).
    public static func build(kind: RechargeKind, session: EcyktSession, fresh: EcyktLogin, card: BoundCard) throws -> RechargeWebSession {
        let state: JSONValue = .object([
            "logintoken": .string(fresh.token),
            "loginInfo": .object([
                "syscustid": .string(fresh.syscustid),
                "isbind": .int(Int64(fresh.isbind)),
                "token": .string(fresh.token),
            ]),
            "schoolid": .string(session.areacode),
            "custInfo": card.raw,
            "custid": .string(card.custid),
        ])
        let json = String(decoding: try state.encoded(), as: UTF8.self)
        var updated = session
        updated.syscustid = fresh.syscustid
        let start: URL
        switch kind {
        case .card: start = SchoolEndpoints.rechargePage
        case .electricity: start = EcyktClient.powerEntryURL(updated, custid: card.custid)
        }
        return RechargeWebSession(kind: kind, startURL: start, stateJSON: json,
                                  userScript: userScript(stateJSON: json), userAgent: session.userAgent)
    }

    static func userScript(stateJSON: String) -> String {
        // JSON is a valid JS literal except for U+2028/U+2029 in strings.
        let literal = stateJSON.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return """
        (function(){
          if (location.origin !== '\(SchoolEndpoints.ecyktOrigin.absoluteString)') { return; }
          var state = \(literal);
          localStorage.setItem('elecampus_state', JSON.stringify(state));
          localStorage.removeItem('elecampus_state_authquery');
          localStorage.removeItem('elecampus_state_backurl');
        })();
        """
    }
}

/// WKWebView navigation allow-list for the recharge pages (the page and every frame in it).
public enum RechargeNavigation {
    public enum Decision: Sendable, Equatable {
        case allow
        /// Hand to `UIApplication.open` (Alipay / WeChat).
        case openExternal
        case cancel
    }

    static let schoolHosts: Set<String> = [SchoolEndpoints.ecyktHost, SchoolEndpoints.portalHost, SchoolEndpoints.casHost]
    static let payApps: Set<String> = ["alipays", "alipay", "weixin"]

    /// - https on ecykt/portal/cas hosts → allow, in the page and in its frames
    /// - `alipays`/`alipay`/`weixin` only on a user tap in the page itself from the ecykt origin
    ///   → open externally; never from a frame
    /// - `about:blank` / `about:srcdoc` → allow (an empty or inline frame loads nothing)
    /// - anything else → cancel, frames included: a frame from another host is a page the
    ///   allow-list never vetted, shown inside the school's
    public static func decide(_ url: URL, isUserTap: Bool, sourceHost: String?, isMainFrame: Bool = true) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https", let host = url.host?.lowercased(), schoolHosts.contains(host) { return .allow }
        if isMainFrame, payApps.contains(scheme), isUserTap, sourceHost?.lowercased() == SchoolEndpoints.ecyktHost { return .openExternal }
        if scheme == "about", ["about:blank", "about:srcdoc"].contains(url.absoluteString) { return .allow }
        return .cancel
    }

    /// Diagnostic line for a cancelled navigation: for http(s) the host only, for any other scheme
    /// the scheme only (an app link's "host" can be an identifier), never the path, query or
    /// fragment, which can carry order ids or tokens.
    public static func blockedEvent(_ url: URL) -> String { blockedEvent(url, event: "recharge.blocked") }

    static func blockedEvent(_ url: URL, event: String) -> String {
        let scheme = sanitized(url.scheme ?? "", limit: 16)
        if scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty {
            return event + " " + scheme + "://" + sanitized(host, limit: 50)
        }
        return event + " " + (scheme.isEmpty ? "unknown" : scheme + ":")
    }

    private static func sanitized(_ text: String, limit: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        return String(text.lowercased().filter { allowed.contains($0) }.prefix(limit))
    }
}

/// WKWebView navigation allow-list for the school login page (the page and every frame in it):
/// https on the three school hosts, default port, no user info. A frame may also be
/// `about:blank` / `about:srcdoc`, which loads nothing. Everything else is cancelled.
public enum SchoolLoginNavigation {
    /// Diagnostic line for a cancelled navigation on the login page (the page or a frame in it),
    /// written like the recharge one: host or scheme only.
    public static func blockedEvent(_ url: URL, isMainFrame: Bool) -> String {
        RechargeNavigation.blockedEvent(url, event: isMainFrame ? "login.blocked" : "login.blockedFrame")
    }

    public static func allows(_ url: URL, isMainFrame: Bool) -> Bool {
        if !isMainFrame, url.scheme?.lowercased() == "about", ["about:blank", "about:srcdoc"].contains(url.absoluteString) { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              RechargeNavigation.schoolHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return true
    }
}
