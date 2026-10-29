import Foundation

// Default TLS validation; no redirects, cookies, cache or application-level retries.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor public final class HTTPSWaterProvider: WaterProvider {
    private let session: URLSession
    public init() {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        options.timeoutIntervalForResource = 20
        options.httpShouldSetCookies = false
        options.urlCache = nil
        session = URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }
    private func post(config: WaterConfig, path: String, frame: Data) async throws -> [String: Any] {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let random = String((0..<6).map { _ in alphabet.randomElement()! })
        let code = try WaterProtocol.wxcode(config: config, frame: frame, random: random)
        let fields = [("wxcode",code),("sign",WaterProtocol.signature(secret: config.secret, wxcode: code)),("sid",config.sid)]
        var request = URLRequest(url: URL(string: "https://isv.lxt6.cn" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.map { "\($0.0)=\(WaterProtocol.encodeForm($0.1))" }.joined(separator: "&").utf8)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw WaterError.networkUncertain }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 65536, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.doubleValue == 0,
              let body = root["data"] as? [String: Any] else { throw WaterError.provider }
        return body
    }
    public func authorize(config: WaterConfig, frame: Data) async throws -> Authorization {
        if let access = config.access {
            guard try WaterProtocol.identity(frame) == config.machineID.uppercased() else {throw WaterError.wrongDevice}
            let body = try await WaterAccessClient().call("authorize",access:access,fields:["frame":frame.upperHex,"operationID":UUID().uuidString])
            guard let machine = body["machineID"] as? String, let id = body["studentID"] as? String,
                  let text = body["payload"] as? String, let payload = Data(strictHex:text) else {throw WaterError.provider}
            return Authorization(machineID:machine,payload:payload,studentID:id)
        }
        let body = try await post(config: config, path: "/ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization", frame: frame)
        guard let machine = body["machineid"] as? String,
              let student = body["studentId"] as? String,
              let hex = body["systemData"] as? String, let payload = Data(strictHex: hex) else { throw WaterError.provider }
        return Authorization(machineID: machine, payload: payload, studentID: student)
    }
    public func settle(config: WaterConfig, frame: Data) async throws -> SettlementReceipt {
        if let access = config.access {
            guard try WaterProtocol.identity(frame) == config.machineID.uppercased() else {throw WaterError.wrongDevice}
            let body = try await WaterAccessClient().call("settle",access:access,fields:["frame":frame.upperHex])
            guard body["settled"] as? Bool == true else {throw WaterError.provider}
            return SettlementReceipt.parse(["pay":body["payFen"] ?? NSNull()])
        }
        let body = try await post(config: config, path: "/ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData", frame: frame)
        return SettlementReceipt.parse(body)
    }
}
