import SwiftUI
import UIKit
import WidgetKit
import XCTest
import Core
@testable import XiaoRiChang

/// 暖橙's widget face (`WarmWidgetFace`): the apricot palette, the electricity bar out of 100 度,
/// red for low electricity only, and the mascot on every face with numbers.
final class WarmWidgetFaceTests: XCTestCase {
    private func rgba(_ color: Color, dark: Bool = false) -> [Int] {
        let resolved = UIColor(color).resolvedColor(with:UITraitCollection(userInterfaceStyle:dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green:&g, blue:&b, alpha:&a)
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }
    private func hex(_ value: UInt32, alpha: Double = 1) -> [Int] {
        [Int(value >> 16 & 0xFF), Int(value >> 8 & 0xFF), Int(value & 0xFF), Int((alpha * 255).rounded())]
    }
    private func model(_ state: WidgetFreshness = .fresh, power: String? = "42.6", card: String? = "86.50") -> CampusWidgetModel {
        CampusWidgetModel(state:state, remainingKWh:power.flatMap { Decimal(string:$0) }, balance:card.flatMap { Decimal(string:$0) })
    }

    // MARK: Palette

    func testWarmIsTheApricotPalette() {
        let p = CampusWidgetPalette.of(.warm)
        XCTAssertEqual(rgba(p.group), hex(0xFFF4EB))
        XCTAssertEqual(rgba(p.group, dark:true), hex(0x211812))
        XCTAssertEqual(rgba(p.ink), hex(0x111111))
        XCTAssertEqual(rgba(p.ink, dark:true), hex(0xF5F5F5))
        XCTAssertEqual(rgba(p.ink2), hex(0x6B625C))
        XCTAssertEqual(rgba(p.ink2, dark:true), hex(0x9A918A))
        XCTAssertEqual(rgba(p.ink3), hex(0xA39A93))
        XCTAssertEqual(rgba(p.ink3, dark:true), hex(0x5E554F))
        XCTAssertEqual(rgba(p.accent), hex(0xF2600B))
        XCTAssertEqual(rgba(p.accent, dark:true), hex(0xFF7A2E))
        XCTAssertEqual(rgba(p.accentText), hex(0xC2470A))
        XCTAssertEqual(rgba(p.accentText, dark:true), hex(0xFF8A45))
        XCTAssertEqual(rgba(p.redLarge), hex(0xE5332A))
        XCTAssertEqual(rgba(p.redLarge, dark:true), hex(0xFF453A))
        XCTAssertEqual(rgba(p.separator), hex(0x6B625C, alpha:0.18))
        XCTAssertEqual(rgba(p.separator, dark:true), hex(0xFFFFFF, alpha:0.10))
        XCTAssertEqual(rgba(p.track), hex(0xF2600B, alpha:0.16))
        XCTAssertEqual(rgba(p.track, dark:true), hex(0xFF7A2E, alpha:0.22))
        XCTAssertEqual(rgba(p.lowTrack), hex(0xE5332A, alpha:0.16))
        XCTAssertEqual(rgba(p.icon), rgba(p.accent), "bolt and creditcard in accent")
        XCTAssertEqual(rgba(p.icon, dark:true), rgba(p.accent, dark:true))
    }

    func testClearKeepsItsPalette() {
        let p = CampusWidgetPalette.of(.clear)
        XCTAssertEqual(rgba(p.group), rgba(ClearPalette.group))
        XCTAssertEqual(rgba(p.ink2), rgba(ClearPalette.ink2))
        XCTAssertEqual(rgba(p.icon), rgba(ClearPalette.accentText))
    }

    // MARK: Which face

    func testWarmDrawsTheWarmFaceAndClearKeepsItsOwn() {
        XCTAssertTrue(CampusWidgetFace.drawsWarm(theme:.warm))
        XCTAssertFalse(CampusWidgetFace.drawsWarm(theme:.clear))
    }

    func testFaces() {
        XCTAssertEqual(WarmWidgetFace.Content.of(.never, medium:false), .signedOut)
        XCTAssertEqual(WarmWidgetFace.Content.of(.never, medium:true), .signedOut)
        XCTAssertEqual(WarmWidgetFace.Content.of(model(power:nil, card:nil), medium:false), .firstRead)
        XCTAssertEqual(WarmWidgetFace.Content.of(model(), medium:false), .numbers)
        XCTAssertEqual(WarmWidgetFace.Content.of(model(.stale), medium:false), .numbers)
        XCTAssertEqual(WarmWidgetFace.Content.of(model(.expired), medium:false), .cardOnly, "small expired: the card alone")
        XCTAssertEqual(WarmWidgetFace.Content.of(model(.expired), medium:true), .numbers)
        XCTAssertEqual(WarmWidgetFace.Content.of(.placeholderFace, medium:false), .numbers, "the grey bars keep the layout")
    }

    func testTheMascotIsOnEveryFaceWithNumbers() {
        XCTAssertTrue(WarmWidgetFace.Content.numbers.cornerMascot)
        XCTAssertTrue(WarmWidgetFace.Content.cardOnly.cornerMascot)
        XCTAssertFalse(WarmWidgetFace.Content.signedOut.cornerMascot, "signed out draws its own, larger")
        XCTAssertFalse(WarmWidgetFace.Content.firstRead.cornerMascot)
        XCTAssertEqual(WarmWidgetFace.signedOutMascot(medium:false), 40)
        XCTAssertEqual(WarmWidgetFace.signedOutMascot(medium:true), 64)
        XCTAssertEqual(WarmWidgetFace.cornerMascot, 20)
    }

    /// Accented, tinted and clear Home Screens draw no mascot at all, in the corner or signed out.
    func testTheMascotIsDrawnOnlyInFullColor() {
        XCTAssertTrue(WarmWidgetFace.drawsMascot(.fullColor))
        XCTAssertFalse(WarmWidgetFace.drawsMascot(.accented))
        XCTAssertFalse(WarmWidgetFace.drawsMascot(.vibrant))
    }

    // MARK: Bar and level

    func testTheBarIsWhatIsLeftOutOf100Clamped() {
        XCTAssertEqual(WarmWidgetFace.barFill(model()), 0.426, accuracy:0.0001)
        XCTAssertEqual(WarmWidgetFace.barFill(model(power:"0")), 0)
        XCTAssertEqual(WarmWidgetFace.barFill(model(power:"100")), 1)
        XCTAssertEqual(WarmWidgetFace.barFill(model(power:"182.5")), 1, "over 100 度: full")
        XCTAssertEqual(WarmWidgetFace.barFill(model(power:"-3")), 0, "below 0: empty")
        XCTAssertEqual(WarmWidgetFace.barFill(model(power:nil)), 0, "no reading: the track alone")
        XCTAssertEqual(WarmWidgetFace.barFill(.placeholderFace), 0, "loading: the track alone")
    }

    func testLowElectricityTurnsTheNumberBarAndTrackRed() {
        let low = model(power:"4.8")
        XCTAssertEqual(WarmWidgetFace.Level.of(low), .low)
        XCTAssertEqual(WarmWidgetFace.Level.of(model()), .normal)
        XCTAssertEqual(WarmWidgetFace.Level.of(model(.expired, power:"4.8")), .expired, "expired greys, never red")
        let p = CampusWidgetPalette.warm
        XCTAssertEqual(rgba(WarmWidgetFace.Level.low.number(p)), rgba(p.redLarge))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.low.unit(p)), rgba(p.redLarge))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.low.fill(p)), rgba(p.redLarge))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.low.track(p)), rgba(p.lowTrack))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.normal.number(p)), rgba(p.ink))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.normal.unit(p)), rgba(p.ink2))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.normal.fill(p)), rgba(p.accent))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.normal.track(p)), rgba(p.track))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.expired.number(p)), rgba(p.ink3))
        XCTAssertEqual(rgba(WarmWidgetFace.Level.expired.fill(p)), rgba(p.ink3))
    }

    func testTheSmallFaceSwapsTheBarForTheFooterOnlyWhenStale() {
        XCTAssertTrue(WarmWidgetFace.smallShowsBar(model()))
        XCTAssertFalse(WarmWidgetFace.smallShowsBar(model(.stale)))
    }
}
