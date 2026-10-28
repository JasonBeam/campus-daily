import Foundation

/// Official server-validated account context for the school's web recharge pages.
public struct CampusWebSession: Sendable {
    public let state: Data
    public let syscustid: String
    public let custid: String
    public let areacode: String
    public let userAgent: String
    public static func create(config: CampusConfig, login: [String:Any], cards: [[String:Any]]) throws -> CampusWebSession {
        try config.validate()
        func text(_ value: Any?) -> String? {
            if let value = value as? String, !value.isEmpty { return value }
            if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
            return nil
        }
        // The official bridge rotates encrypted identifiers. Compare neither ciphertext
        // with the saved input nor ciphertext from separate responses. These values
        // come only from the authenticated login and bound-card endpoints.
        guard let owner = text(login["syscustid"]), text(login["isbind"]) == "1" else { throw CampusError.expired }
        let matches = cards.filter { text($0["custid"]) == config.custid }
        let card: [String:Any]
        if !config.custid.isEmpty {
            if matches.count == 1 { card = matches[0] }
            else {
                guard matches.isEmpty, cards.count == 1 else { throw CampusError.ambiguous }
                card = cards[0]
            }
        } else {
            guard cards.count == 1 else { throw CampusError.ambiguous }
            card = cards[0]
        }
        guard let custid = text(card["custid"]) else { throw CampusError.response }
        if let cardOwner = text(card["syscustid"]), cardOwner != owner { throw CampusError.expired }
        var info = login
        if info["timestamp"] == nil, !config.timestamp.isEmpty { info["timestamp"] = config.timestamp }
        // AuthMini's official implementation preserves the verified input token.
        let object: [String:Any] = ["logintoken":config.accToken,"loginInfo":info,
            "schoolid":config.areacode,"custInfo":card,"custid":custid]
        let data = try JSONSerialization.data(withJSONObject:object)
        guard data.count <= 262144 else { throw CampusError.response }
        return CampusWebSession(state:data,syscustid:owner,custid:custid,areacode:config.areacode,userAgent:config.userAgent)
    }
    public func rechargeURL(power: Bool) -> URL {
        if !power { return URL(string:CampusProvider.base + "/ykt-view/recharge?isbind=1")! }
        var parts = URLComponents(string:CampusProvider.base + "/ykt-mini/api/electricnew/getPowerUrl")!
        parts.queryItems = [URLQueryItem(name:"custid",value:custid),URLQueryItem(name:"syscustid",value:syscustid)]
        return parts.url!
    }
    public var bootstrapScript: String {
        let payload = state.base64EncodedString()
        return """
        (()=>{if(location.protocol!=="https:"||location.hostname!=="ecykt.gdbtu.edu.cn")return;
        const data=Uint8Array.from(atob('\(payload)'),c=>c.charCodeAt(0));
        const context=JSON.parse(new TextDecoder().decode(data));
        localStorage.setItem('elecampus_state',JSON.stringify(context));
        localStorage.removeItem('elecampus_state_authquery');
        localStorage.removeItem('elecampus_state_backurl');})();
        """
    }
}
