//
//  OnboardingDemo.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

#if DEBUG
import SwiftUI
import Core

/// campusdaily://demo/onboard/{1,1-filled,1-saved,1-loading,1-wrong,1-locked,1-site,1-unknown,3,3-nolocation,3-missing,3-samename,
/// 3-samename-picked,3-meter-*,done}
/// Synthetic account and dorm; the primary button only moves to the next step.
enum OnboardingDemo {
    static func handle(_ url: URL) -> (OnboardingView.Step, OnboardingView.Preview)? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "onboard" else { return nil }
        var preview = OnboardingView.Preview(dorm:"3 栋 108")
        let name = parts.count > 1 ? parts[1] : "1"
        switch name {
        case "3": preview.dormLocation = "北校区 · 东苑公寓 · 3 栋 · 108"; return (.dorm, preview)
        case "3-nolocation": return (.dorm, preview)
        case "3-missing": preview.dorm = nil; return (.dorm, preview)
        case "3-samename", "3-samename-picked":
            // Same-name meter picker: one name in two apartments, told apart by location.
            preview.powerChoices = [LocationChoice(id:"preview-0", title:"3 栋 108", location:"北校区 · 东苑公寓 · 3 栋 · 108"),
                                   LocationChoice(id:"preview-1", title:"3 栋 108", location:"北校区 · 西苑公寓 · 3 栋 · 108")]
            if name == "3-samename-picked" { preview.picked = "preview-1" }
            return (.dorm, preview)
        case "3-meter-finding", "3-meter-ask", "3-meter-ask-picked", "3-meter-slow", "3-meter-unfinished", "3-meter-ask-mixed":
            // The meter under the dorm (synthetic 99 栋 991): looking, two apartments to choose
            // from (one picked), the school too slow, one apartment not read, one apartment's room
            // and one halted before its rooms.
            preview.dorm = "99 栋 991"
            switch name {
            case "3-meter-finding": preview.meter = .finding
            case "3-meter-slow": preview.meter = .failed(MeterPageText.tooSlow)
            case "3-meter-unfinished": preview.meter = .failed(MeterPageText.unfinished(.apartment))
            case "3-meter-ask-mixed":
                if let question = MeterQuestion(CampusModel.demoMixedStop, address:CampusModel.demoAddress) { preview.meter = .ask(question) }
            default:
                if let question = MeterQuestion(CampusModel.demoApartmentStop, address:CampusModel.demoAddress) {
                    preview.meter = .ask(question)
                    if name == "3-meter-ask-picked" { preview.meterPicked = question.rows.last?.id }
                }
            }
            return (.dorm, preview)
        case "1-filled", "1-loading", "1-wrong", "1-locked", "1-site", "1-unknown", "1-fallback":
            // The login form's states; 1-locked, 1-site and 1-unknown are the causes a refused
            // login is said by (1-fallback, the old name, is 1-unknown). Nothing is sent.
            preview.account = "99100991"
            preview.password = name == "1-wrong" ? "" : "demo-password"
            preview.savePassword = name != "1-wrong"
            let states: [String: SchoolLoginState] = ["1-loading":.loading, "1-wrong":.wrong, "1-locked":.blocked(.locked),
                                                      "1-site":.blocked(.needsSchoolSite), "1-unknown":.blocked(.unknown),
                                                      "1-fallback":.blocked(.unknown)]
            preview.loginState = states[name] ?? .idle
            return (.login, preview)
        case "1-saved":
            // A password saved on this phone: the account is filled in and the box ticked.
            preview.saved = SchoolAccount(account:"99100991", password:"demo-password")
            return (.login, preview)
        case "done": return (.done, preview)
        default: return (.login, preview)
        }
    }
}
#endif
