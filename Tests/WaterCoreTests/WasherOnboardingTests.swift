import XCTest
@testable import WaterCore

final class WasherOnboardingTests: XCTestCase {
    private let code = "https://q.ujing.com.cn/ucqrc/index.html?cd=000000000000000001"
    func testOfficialLabelAccepted() throws { try WasherQRCode.validate(code) }
    func testMultipleMachineIdentifiersRejected() {
        XCTAssertThrowsError(try WasherQRCode.validate(code + "&cd=000000000000000002"))
    }
    func testOtherHostAndEmbeddedCredentialsRejected() {
        XCTAssertThrowsError(try WasherQRCode.validate(code.replacingOccurrences(of:"q.ujing.com.cn",with:"q.ujing.com.cn.example.org")))
        XCTAssertThrowsError(try WasherQRCode.validate(code.replacingOccurrences(of:"https://",with:"https://account@")))
    }
    func testFragmentAndAlternatePortRejected() {
        XCTAssertThrowsError(try WasherQRCode.validate(code + "#another-machine"))
        XCTAssertThrowsError(try WasherQRCode.validate(code.replacingOccurrences(of:".cn/",with:".cn:8443/")))
    }
    func testMissingCodeRejected() {
        XCTAssertThrowsError(try WasherQRCode.validate("https://q.ujing.com.cn/ucqrc/index.html"))
    }
    func testSharedWaterProfileDoesNotSerializeIdentity() throws {
        let legacy = WaterConfig(secret:"fixture-shared-key",sid:"fixture-vendor",studentID:"fixture-student",schoolID:"fixture-school",machineID:"AABBCCDD",bleName:"fixture-ble",typeID:1,version:1)
        let profile = WaterPlatformProfile(legacy:legacy)
        let data = try JSONEncoder().encode(profile)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(Set(root.keys),Set(["secret","sid","bleName","typeID","version"]))
        let value = try profile.configuration(student:"another-student",school:"another-school",machine:"11223344")
        XCTAssertEqual(value.studentID,"another-student")
        XCTAssertEqual(value.machineID,"11223344")
    }
    func testAnOrderCannotFollowAnotherAccountOrMachine() {
        let first = LaundryConfig(headers:["Authorization":"Bearer fixture-account-one"],qrCode:code,deviceId:"fixture-device")
        let other = LaundryConfig(headers:["Authorization":"Bearer fixture-account-two"],qrCode:code,deviceId:"fixture-device")
        let otherDevice = LaundryConfig(headers:first.headers,qrCode:code,deviceId:"fixture-other-device")
        var record = LaundryCheckoutRecord(deviceId:first.deviceId,programId:1,programName:"fixture",expectedPrice:1,createdAt:Date(),stage:.created)
        record.credentialIdentity = first.credentialIdentity
        XCTAssertTrue(record.belongs(to:first))
        XCTAssertFalse(record.belongs(to:other))
        XCTAssertFalse(record.belongs(to:otherDevice))
    }
}
