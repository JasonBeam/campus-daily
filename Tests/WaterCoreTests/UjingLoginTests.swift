import XCTest
@testable import WaterCore

private final class LoginProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestSeen: URLRequest?
    nonisolated(unsafe) static var reply = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestSeen = request
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class UjingLoginTests: XCTestCase {
    private let client = "00000000-0000-0000-0000-000000000001"
    private let token = "fixture-token-never-sent-to-a-real-server"
    private func envelope(temporary: Bool = false, id: Any = 123) -> [String:Any] {
        ["code":0,"data":["id":id,"userId":456,"token":token,"isTempToken":temporary]]
    }
    private func provider(reply: [String:Any]) throws -> UjingLoginProvider {
        LoginProtocolStub.reply = try JSONSerialization.data(withJSONObject:reply)
        LoginProtocolStub.requestSeen = nil
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LoginProtocolStub.self]
        return UjingLoginProvider(clientID:client,userAgent:"XiaoRiChang/test",session:URLSession(configuration:config))
    }
    func testNormalSMSRequestContainsNoChallengeDisablingFields() async throws {
        let api = try provider(reply:["code":0,"data":NSNull()])
        try await api.sendCode(mobile:"10000000000")
        let request = try XCTUnwrap(LoginProtocolStub.requestSeen)
        XCTAssertEqual(request.httpMethod,"GET")
        XCTAssertEqual(request.url?.host,"phoenix.ujing.online")
        let items = try XCTUnwrap(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems)
        XCTAssertEqual(Set(items.map(\.name)),Set(["mobile","type"]))
        XCTAssertEqual(request.value(forHTTPHeaderField:"x-app-code"),"ZI")
        XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField:"x-user-geo"))
    }
    func testLoginReturnsDistinctAuthoritativeAccountIdentifiers() async throws {
        let api = try provider(reply:envelope())
        let account = try await api.login(mobile:"10000000000",captcha:"123456")
        XCTAssertEqual(account.id,"123"); XCTAssertEqual(account.businessUserID,"456")
        XCTAssertEqual(LoginProtocolStub.requestSeen?.httpMethod,"POST")
        XCTAssertEqual(LoginProtocolStub.requestSeen?.url?.path,"/api/v1/login")
    }
    func testTemporaryTokenCannotCompleteLogin() throws {
        XCTAssertThrowsError(try UjingLoginProvider.account(root:envelope(temporary:true),clientID:client,userAgent:"test"))
    }
    func testBooleanAccountIdentifierRejected() throws {
        XCTAssertThrowsError(try UjingLoginProvider.account(root:envelope(id:true),clientID:client,userAgent:"test"))
    }
    func testMalformedPhoneDoesNotMakeARequest() async throws {
        let api = try provider(reply:["code":0])
        do { try await api.sendCode(mobile:"not-a-phone"); XCTFail("should reject") } catch {}
        XCTAssertNil(LoginProtocolStub.requestSeen)
    }
    func testStableAccountIdentitySurvivesTokenRenewal() {
        let qr = "https://q.ujing.com.cn/ucqrc/index.html?cd=000000000000000001"
        let first = LaundryConfig(headers:["Authorization":"Bearer first-token"],qrCode:qr,deviceId:"device",accountID:"123")
        let renewed = LaundryConfig(headers:["Authorization":"Bearer renewed-token"],qrCode:qr,deviceId:"device",accountID:"123")
        let other = LaundryConfig(headers:renewed.headers,qrCode:qr,deviceId:"device",accountID:"456")
        XCTAssertEqual(first.credentialIdentity,renewed.credentialIdentity)
        XCTAssertNotEqual(first.credentialIdentity,other.credentialIdentity)
    }
}
