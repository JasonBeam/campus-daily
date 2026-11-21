//
//  SampleSettingsTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import SwiftUI
import Core
@testable import XiaoRiChang

/// Settings and 校园充值 in the sample (`SampleMode`): nothing says signed in, nothing promises
/// a refresh that never comes, and no switch changes.
@MainActor
final class SampleSettingsTests: XCTestCase {
    /// 暖橙's 学校账号 row says 示例账号 in the sample, never 已登录.
    func testWarmAccountRowSaysSampleAccountInTheSample() {
        XCTAssertEqual(AccountText.sampleAccount, "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:true, account:nil, sample:true), "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:false, account:nil, sample:true), "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:true, account:nil, sample:false), "已登录")
        XCTAssertEqual(AccountText.row(signedIn:false, account:nil, sample:false), "去登录")
    }

    /// 清爽's 校园充值 promises 返回后会刷新余额 outside the sample only (`CampusTopUpFlow` never
    /// refreshes in it).
    func testClearTopUpNoteDropsTheRefreshInTheSample() {
        XCTAssertEqual(ClearCampusTopUpText.note(sample:false), ClearCampusTopUpText.note)
        XCTAssertTrue(ClearCampusTopUpText.note(sample:false).contains("返回后会刷新余额"))
        XCTAssertEqual(ClearCampusTopUpText.note(sample:true),
                       "点击后将复制“e广工商大办事大厅”并打开微信；在聊天列表下拉点击该小程序，未显示时可搜索并粘贴。付款和到账以学校官方结果为准。")
        XCTAssertFalse(ClearCampusTopUpText.note(sample:true).contains("刷新"))
        XCTAssertTrue(ClearCampusTopUpText.note(sample:true).contains(CampusTopUp.serviceName))
    }

    /// 暖橙's 学校洗衣机 switch in the sample: the value stays and the blocked message comes up,
    /// like the other switches.
    func testSchoolLaundrySwitchIsBlockedInTheSample() {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        XCTAssertEqual(sample.enter(), .entered)
        var stored: Bool?
        let laundrySwitch = SchoolLaundrySwitch(laundry:Self.laundry(), preview:HomeData.sample(),
                                                previewOn:Binding(get:{ stored }, set:{ stored = $0 }), sample:sample)
        let before = laundrySwitch.isOn
        laundrySwitch.binding.wrappedValue = !before
        XCTAssertEqual(laundrySwitch.isOn, before)
        XCTAssertNil(stored)
        XCTAssertEqual(sample.blocked, .bindWasher)
    }

    /// Outside the sample the DEBUG demo's switch still flips locally.
    func testSchoolLaundrySwitchFlipsOutsideTheSample() {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        var stored: Bool?
        let laundrySwitch = SchoolLaundrySwitch(laundry:Self.laundry(), preview:HomeData.sample(),
                                                previewOn:Binding(get:{ stored }, set:{ stored = $0 }), sample:sample)
        let before = laundrySwitch.isOn
        laundrySwitch.binding.wrappedValue = !before
        XCTAssertEqual(stored, !before)
        XCTAssertNil(sample.blocked)
    }

    private static func laundry() -> LaundryModel {
        let services = CampusServices.sample()
        return LaundryModel(services:services, reminders:Reminders.sample(defaults:services.defaults), activities:nil)
    }
}
