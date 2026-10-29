import XCTest
@testable import WaterCore

private final class AccessProtocolStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        let html = request.value(forHTTPHeaderField:"X-Fixture-HTML") == "1"
        let response = HTTPURLResponse(url:request.url!,statusCode:html ? 403 : 502,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data((html ? "<html>private upstream detail</html>" : #"{"error":"school_unavailable"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class EndpointProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var failPrimaryHealth = false
    nonisolated(unsafe) static var failAuthorization = false
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        Self.requests.append(request)
        let isHealth = request.url?.path == "/health"
        if isHealth && Self.failPrimaryHealth && request.url?.host == "campus-api.070688.xyz" {
            client?.urlProtocol(self,didFailWithError:URLError(.cannotFindHost));return
        }
        if !isHealth && Self.failAuthorization {
            client?.urlProtocol(self,didFailWithError:URLError(.timedOut));return
        }
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!
        let body = isHealth ? #"{"service":"campus-daily-access","protocol":1,"configured":true}"# : #"{"operation":null,"transactionsEnabled":true}"#
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WaterAccessTests: XCTestCase {
    private func campus() throws -> CampusConfig {try JSONDecoder().decode(CampusConfig.self,from:Data(#"{"syscustid":"fixture-owner","acc_token":"fixture-token","custid":"fixture-card","areacode":"450010"}"#.utf8))}
    private func access(owner: String) throws -> WaterAccessSession {
        let raw: [String:Any] = ["token":String(repeating:"A",count:43),"campusOwner":owner,"expiresAt":Int64(Date().addingTimeInterval(3600).timeIntervalSince1970*1000),"studentID":"fixture-student","schoolID":"fixture-school","bleName":"fixture-ble","typeID":1,"version":1]
        return try JSONDecoder().decode(WaterAccessSession.self,from:JSONSerialization.data(withJSONObject:raw))
    }
    func testRemoteConfigurationRequiresNoSharedSigningKeyAndPersists() throws {
        let own = try access(owner:campus().waterAccessOwner)
        let value = try WaterPlatformProfile(access:own).configuration(student:own.studentID,school:own.schoolID,machine:"11223344")
        try value.validate();XCTAssertEqual(value.secret,"");XCTAssertEqual(value.sid,"")
        let restored = try JSONDecoder().decode(WaterConfig.self,from:JSONEncoder().encode(value))
        XCTAssertEqual(restored.access,own);try restored.validate()
        XCTAssertThrowsError(try WaterPlatformProfile(access:own).configuration(student:"another-student",school:own.schoolID,machine:"11223344"))
    }
    @MainActor func testAnotherCampusAccountCannotReuseAnAccessSession() async throws {
        let wrong = try access(owner:String(repeating:"b",count:64))
        do {_ = try await DormOnboardingProvider().identity(campus:campus(),seed:WaterPlatformProfile(access:wrong));XCTFail("Must reject before network")}
        catch {XCTAssertEqual(error as? WaterError,.invalidConfig)}
    }
    @MainActor func testVerifiedSessionIdentityCanLoadWithoutBundledPlatformProfile() async throws {
        let own = try access(owner:campus().waterAccessOwner)
        let identity = try await DormOnboardingProvider().identity(campus:campus(),seed:WaterPlatformProfile(access:own))
        XCTAssertEqual(identity.student,own.studentID);XCTAssertEqual(identity.school,own.schoolID)
        XCTAssertTrue(own.isCurrent)
    }
    @MainActor func testGatewayFailureRetainsSafeStageWithoutClaimingAnExpiredLogin() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [AccessProtocolStub.self]
        do {_ = try await WaterAccessClient(session:URLSession(configuration:config)).connect(campus());XCTFail("Must report failure")}
        catch let failure as WaterAccessError {
            XCTAssertEqual(failure.status,502);XCTAssertEqual(failure.code,"school_unavailable")
            XCTAssertFalse(failure.localizedDescription.contains("过期"))
        }
    }
    @MainActor func testNonJSONGatewayFailureDoesNotEchoPrivateResponseBody() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [AccessProtocolStub.self]
        config.httpAdditionalHeaders = ["X-Fixture-HTML":"1"]
        do {_ = try await WaterAccessClient(session:URLSession(configuration:config)).connect(campus());XCTFail("Must reject HTML")}
        catch let failure as WaterAccessError {
            XCTAssertEqual(failure.status,403);XCTAssertEqual(failure.code,"invalid_response")
            XCTAssertFalse(failure.localizedDescription.contains("private upstream"))
        }
    }
    @MainActor func testServiceFallbackProbesContainNoCredentialsBeforeChoosingOnePOST() async throws {
        EndpointProtocolStub.requests = [];EndpointProtocolStub.failPrimaryHealth = true;EndpointProtocolStub.failAuthorization = false
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [EndpointProtocolStub.self]
        let api = WaterAccessClient(session:URLSession(configuration:config),probeService:true)
        _ = try await api.call("status",access:access(owner:campus().waterAccessOwner),fields:[:])
        let probes = EndpointProtocolStub.requests.filter {$0.url?.path == "/health"}
        XCTAssertEqual(probes.count,2)
        XCTAssertTrue(probes.allSatisfy {$0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField:"Authorization") == nil})
        let posts = EndpointProtocolStub.requests.filter {$0.httpMethod == "POST"}
        XCTAssertEqual(posts.count,1);XCTAssertEqual(posts.first?.url?.host,"campus-daily-access.jasonbeam-campus.workers.dev")
    }
    @MainActor func testUncertainAuthorizationIsNeverRetriedAcrossServiceHosts() async throws {
        EndpointProtocolStub.requests = [];EndpointProtocolStub.failPrimaryHealth = false;EndpointProtocolStub.failAuthorization = true
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [EndpointProtocolStub.self]
        let api = WaterAccessClient(session:URLSession(configuration:config),probeService:true)
        do {_ = try await api.call("authorize",access:access(owner:campus().waterAccessOwner),fields:[:]);XCTFail("Must report uncertainty")}
        catch {XCTAssertEqual(error as? WaterError,.networkUncertain)}
        XCTAssertEqual(EndpointProtocolStub.requests.filter {$0.httpMethod == "POST"}.count,1)
        XCTAssertTrue(EndpointProtocolStub.requests.allSatisfy {$0.url?.host == "campus-api.070688.xyz"})
        EndpointProtocolStub.failAuthorization = false
    }
    func testBootstrapRequiresAnExactResidenceAndAdvertisesServiceReadiness() throws {
        let names = ["示例校区","2栋","五楼","504"]
        let path = names.enumerated().map { ["id":"fixture-\($0.offset)","name":$0.element] }
        let root: [String:Any] = ["levels":path.map {[$0]},"path":path,"machines":[["id":"11223344","name":"fixture","mac":"11:22:33:44:55:66"]],"matched":true,"transactionsEnabled":false]
        let boot = try WaterAccessBootstrap.parse(root,residence:"示例校区2栋3号5层504房")
        XCTAssertTrue(boot.matched);XCTAssertEqual(boot.path.count,4);XCTAssertFalse(boot.transactionsEnabled)
        XCTAssertThrowsError(try WaterAccessBootstrap.parse(root,residence:"其他校区2栋5层504房"))
        var partial = root;partial["matched"] = false
        XCTAssertThrowsError(try WaterAccessBootstrap.parse(partial,residence:"示例校区2栋5层504房"))
    }
}
