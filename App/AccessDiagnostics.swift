#if CAMPUS_ACCESS_DIAGNOSTICS
import Foundation
import WaterCore

private final class AccessNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {completionHandler(nil)}
}

/// Opt-in local acceptance build only. Never exports credentials or changes a binding.
@MainActor enum AccessDiagnostics {
    static func waterBilling(campus: CampusModel) async {
        var report: [String:Any] = ["startedAt":ISO8601DateFormatter().string(from:Date()),"transactionsAttempted":false]
        do {
            guard let config = campus.onboardingLogin else { throw OnboardingError.login }
            let options = URLSessionConfiguration.ephemeral
            options.timeoutIntervalForRequest = 15; options.httpShouldSetCookies = false
            let session = URLSession(configuration:options,delegate:AccessNoRedirect(),delegateQueue:nil)
            defer { session.invalidateAndCancel() }
            func read(_ path: String, extra: [String:Any] = [:]) async throws -> [String:Any] {
                guard ["/api/water/gdwater/getWaterMoney","/api/sign/wxschoolsign/errOrder"].contains(path) else { throw CampusError.configuration }
                var payload: [String:Any] = ["syscustid":config.syscustid,"custid":config.custid,"acc_token":config.accToken,"timestamp":config.timestamp]
                extra.forEach { payload[$0.key] = $0.value }
                var request = URLRequest(url:URL(string:CampusProvider.base+"/ykt-mini"+path)!)
                request.httpMethod = "POST"; request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.setValue(config.accToken,forHTTPHeaderField:"acc_token")
                request.setValue(config.userAgent,forHTTPHeaderField:"User-Agent")
                request.httpBody = try JSONSerialization.data(withJSONObject:payload)
                let (bytes,response) = try await session.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 1048576,
                      let body = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw CampusError.response }
                return body
            }
            let money = try await read("/api/water/gdwater/getWaterMoney")
            report["waterMoney"] = money
            if money["code"] as? Int == 0, let data = money["data"] as? [String:Any], let business = data["busicode"] {
                report["failedDebits"] = try await read("/api/sign/wxschoolsign/errOrder",extra:["busicode":business])
            }
            report["completed"] = true
        } catch { report["completed"] = false; report["errorClass"] = String(describing:type(of:error)) }
        report["finishedAt"] = ISO8601DateFormatter().string(from:Date())
        let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("water-billing-read-only-private.json")
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    static func run(campus: CampusModel) async {
        var report: [String:Any] = ["startedAt":ISO8601DateFormatter().string(from:Date()),"transactionsAttempted":false]
        do {
            guard let config = campus.onboardingLogin else {throw OnboardingError.login}
            report["schoolLoginSaved"] = true
            // Compare the school's direct response with the broker response;
            // report only status codes, never signed identity data or tokens.
            do {
                let options = URLSessionConfiguration.ephemeral
                options.timeoutIntervalForRequest = 15;options.httpShouldSetCookies = false
                let session = URLSession(configuration:options,delegate:AccessNoRedirect(),delegateQueue:nil)
                var request = URLRequest(url:URL(string:CampusProvider.base+"/ykt-mini/api/customer/getSignData")!)
                request.httpMethod = "POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.setValue(config.accToken,forHTTPHeaderField:"acc_token")
                request.httpBody = try JSONSerialization.data(withJSONObject:["syscustid":config.syscustid,"custid":config.custid,"acc_token":config.accToken,"timestamp":config.timestamp])
                let (bytes,response) = try await session.data(for:request)
                report["directSchoolHTTP"] = (response as? HTTPURLResponse)?.statusCode
                if bytes.count <= 65536, let body = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] {
                    report["directSchoolCode"] = body["code"] as? Int
                }
                session.invalidateAndCancel()
            } catch {report["directSchoolCheck"] = "unavailable"}
            let access = try await WaterAccessClient().connect(config)
            report["ownIdentityVerified"] = access.campusOwner == config.waterAccessOwner
            let seed = WaterPlatformProfile(access:access), provider = DormOnboardingProvider()
            let address = PortalDormAddress.parse(config.portalDormAddress)
            report["portalResidenceSaved"] = address != nil
            var parent = access.schoolID
            var matched = 0
            for level in 0..<4 {
                let rows = try await provider.options(parent:parent,rooms:level == 3,seed:seed)
                report["level\(level)Count"] = rows.count
                guard let address else {break}
                let selected = rows.filter {address.matches($0.name,level:level)}
                guard selected.count == 1 else {break}
                parent = selected[0].id; matched += 1
            }
            report["matchedLevels"] = matched
            if matched == 4 {
                let machines = try await provider.machines(room:parent,school:access.schoolID,seed:seed)
                report["machineCount"] = machines.count
            }
            let status = try await WaterAccessClient().call("status",access:access,fields:[:])
            report["transactionsEnabled"] = status["transactionsEnabled"] as? Bool ?? false
            report["completed"] = true
        } catch {
            report["completed"] = false
            report["error"] = (error as? LocalizedError)?.errorDescription ?? "read_only_check_failed"
            if let failure = error as? WaterAccessError {
                report["httpStatus"] = failure.status; report["serviceCode"] = failure.code
            }
        }
        report["finishedAt"] = ISO8601DateFormatter().string(from:Date())
        let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("access-read-only-check.json")
        if let bytes = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            try? bytes.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
#endif
