import XCTest
@testable import WaterCore

private final class DirectIdentityProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hosts:[String] = []
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        Self.hosts.append(request.url!.host!)
        let text:String
        if request.url?.host == "ecykt.gdbtu.edu.cn" {
            text = #"{"code":0,"data":{"appdata":{"vsuppid":"fixture","appid":"fixture-app","userId":"fixture-user","deptId":"fixture-dept","username":"fixture-name","phone":"fixture-phone"}}}"#
        } else if request.url?.host == "isv.lxt6.cn" && request.url?.path == "/AECC/GDBusinessSchool/getUserMsg" {
            let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            let fields=Dictionary(uniqueKeysWithValues:q.map{($0.name,$0.value ?? "")})
            XCTAssertEqual(fields["sid"],"fixture-provider")
            XCTAssertEqual(fields["sign"],WaterProtocol.signature(secret:"fixture-secret",wxcode:fields["wxcode"]!))
            text = #"{"Code":0,"Data":{"studentid":"own-user","schoolid":20021}}"#
        } else {XCTFail("Direct onboarding must not contact a custom service");text="{}"}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(text.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class DirectPlatformTests:XCTestCase {
    private func platform() throws -> WaterPlatformProfile {
        try .parseImport(Data(#"{"secret":"fixture-secret","sid":"fixture-provider","bleName":"fixture-ble","typeID":1,"version":1}"#.utf8))
    }
    private func previous() throws -> WaterConfig {
        let session=try JSONDecoder().decode(WaterAccessSession.self,from:Data(#"{"token":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","campusOwner":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expiresAt":1,"studentID":"own-user","schoolID":"20021","bleName":"fixture-ble","typeID":1,"version":1}"#.utf8))
        return try WaterPlatformProfile(access:session).configuration(student:"own-user",school:"20021",machine:"11223344")
    }
    func testExpiredBrokerSessionCanMigrateWithoutChangingControllerOrIdentity() throws {
        let old=try previous()
        let next=try platform().migrateToDirect(old,owner:String(repeating:"a",count:64),student:"own-user",school:"20021",unresolved:false)
        XCTAssertNil(next.access);XCTAssertEqual(next.machineID,old.machineID);XCTAssertEqual(next.studentID,old.studentID)
        XCTAssertEqual(next.secret,"fixture-secret");try next.validate()
    }
    func testWrongAccountOrPendingOperationCannotMigrate() throws {
        let old=try previous(),p=try platform(),owner=String(repeating:"a",count:64)
        XCTAssertThrowsError(try p.migrateToDirect(old,owner:owner,student:"other-user",school:"20021",unresolved:false))
        XCTAssertThrowsError(try p.migrateToDirect(old,owner:String(repeating:"b",count:64),student:"own-user",school:"20021",unresolved:false))
        XCTAssertThrowsError(try p.migrateToDirect(old,owner:owner,student:"own-user",school:"other-school",unresolved:false))
        XCTAssertThrowsError(try p.migrateToDirect(old,owner:owner,student:"own-user",school:"20021",unresolved:true))
    }
    @MainActor func testFreshIdentityUsesOnlySchoolAndWaterPlatformWithBundledParameters() async throws {
        DirectIdentityProtocol.hosts=[]
        let settings=URLSessionConfiguration.ephemeral;settings.protocolClasses=[DirectIdentityProtocol.self]
        let c=try JSONDecoder().decode(CampusConfig.self,from:Data(#"{"syscustid":"fixture-owner","acc_token":"fixture-token","custid":"fixture-card","areacode":"450010"}"#.utf8))
        let who=try await DormOnboardingProvider(session:URLSession(configuration:settings)).identity(campus:c,seed:platform())
        XCTAssertEqual(who.student,"own-user");XCTAssertEqual(who.school,"20021")
        XCTAssertEqual(DirectIdentityProtocol.hosts,["ecykt.gdbtu.edu.cn","isv.lxt6.cn"])
    }
}
