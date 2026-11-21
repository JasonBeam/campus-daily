//
//  ShowerModel+Start.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import Foundation
import Core

/// One explicit 开始洗澡 (a tap on home, the 热水洗澡 screen or the page, 开始下一次洗澡, Siri),
/// carried from the tap to the engine. It holds the binding and the account generation of the
/// tap: the start runs with those or not at all, never with whatever is current later. Its
/// permit (`ShowerStartPermit`) is what the engine consumes right before the authorize request.
struct ShowerStartIntent {
    enum Entry: Equatable { case home, page, retry, shortcut }
    enum Kind: Equatable { case start, next }
    enum Phase: Equatable {
        /// The explainer is up (Bluetooth never asked): nothing created, nothing asked.
        case awaitingConfirm
        /// 好，开始 was tapped: the system alert is up.
        case awaitingPermission
        /// Handed to the page and the engine.
        case starting
    }

    let id = UUID()
    let entry: Entry
    let kind: Kind
    let binding: ShowerBinding
    let generation: Int
    /// No start has matched this dorm's controller yet (`ShowerBinding.matchedAt`).
    let firstCheck: Bool
    let permit = ShowerStartPermit()
    var phase: Phase
    /// Tapped outside the page: the page is brought up with it (not for a first check).
    var showingPage = false
    /// A DEBUG demo's explainer: confirming it asks for nothing.
    var demo = false
    /// Its page effect has made the engine call (once).
    var launched = false

    init(entry: Entry, kind: Kind, binding: ShowerBinding, generation: Int, firstCheck: Bool, phase: Phase, showingPage: Bool) {
        self.entry = entry; self.kind = kind; self.binding = binding; self.generation = generation
        self.firstCheck = firstCheck; self.phase = phase; self.showingPage = showingPage
    }
}

/// The scene as a start cares about it: the system alert makes the app inactive (the start
/// waits); the background takes the start back.
enum ShowerScene { case active, inactive, background }

/// What a tap on 开始洗澡 did, so the caller knows where the user has to look.
enum ShowerStartTap: Equatable {
    /// The start runs; a first check shows on the 热水洗澡 screen.
    case started(firstCheck: Bool)
    /// The explainer is up.
    case explainer
    /// Refused before anything (no Bluetooth permission): the line under 开始洗澡 says why.
    case refused
    /// Another start is already under way: this tap joins it.
    case joined
    /// Not now (`mayStart`): the page shows what is going on.
    case notAllowed
}

extension ShowerModel {
    /// The explainer's start, while it waits for 好，开始 or 等会儿.
    var explainerIntent: ShowerStartIntent? {
        startSlot?.phase == .awaitingConfirm ? startSlot : nil
    }

    /// 开始洗澡 / 再试一次 / 开始下一次洗澡 tapped. `showingPage`: the tap came from a screen
    /// other than the page (the page is brought up the way home's buttons do).
    @discardableResult
    func tapStart(_ entry: ShowerStartIntent.Entry, kind: ShowerStartIntent.Kind = .start, showingPage: Bool = false) -> ShowerStartTap {
        // One start at a time: a tap while one waits or runs is the same start.
        if let slot = startSlot {
            if showingPage, slot.phase == .starting, page.presented { pageWanted += 1 }
            return .joined
        }
        let allowed = kind == .next ? mayStartNext : mayStart && (entry != .retry || page.mayRetry)
        guard allowed, let binding else {
            // Something is going on already: the page shows it, as before.
            if kind == .start, entry != .retry, !state.canStart {
                if showingPage { pageEventShowingPage(.startTapped) } else { pageEvent(.startTapped) }
            }
            return .notAllowed
        }
        switch bluetoothAccess.authorization {
        case .denied:
            pageEvent(.checkFailed(.noPermission))
            return .refused
        case .notDetermined:
            startSlot = makeIntent(entry, kind, binding, phase:.awaitingConfirm, showingPage:showingPage)
            return .explainer
        case .allowed:
            let intent = makeIntent(entry, kind, binding, phase:.starting, showingPage:showingPage)
            startSlot = intent
            launch(intent)
            return .started(firstCheck:intent.firstCheck)
        }
    }

    private func makeIntent(_ entry: ShowerStartIntent.Entry, _ kind: ShowerStartIntent.Kind, _ binding: ShowerBinding,
                            phase: ShowerStartIntent.Phase, showingPage: Bool) -> ShowerStartIntent {
        ShowerStartIntent(entry:entry, kind:kind, binding:binding, generation:startGeneration,
                          firstCheck:kind == .start && binding.matchedAt == nil, phase:phase, showingPage:showingPage)
    }

    /// Hands the slot's start to the page, whose effect makes the one engine call.
    private func launch(_ intent: ShowerStartIntent) {
        guard startSlot?.id == intent.id else { return }
        startSlot?.phase = .starting
        pageStartID = intent.id
        let event: ShowerPageEvent
        switch (intent.kind, intent.entry) {
        case (.next, _): event = .startNextTapped
        case (.start, .retry): event = .retryTapped
        case (.start, _): event = intent.firstCheck ? .firstCheckTapped : .startTapped
        }
        // A first check stays on the 热水洗澡 screen until the number matched.
        if intent.showingPage, !intent.firstCheck { pageEventShowingPage(event) } else { pageEvent(event) }
        // The flow took no start (the page refused it): nothing runs, nothing waits.
        if startSlot?.id == intent.id, startSlot?.launched == false, startTaskID != intent.id {
            startSlot = nil
            if pageStartID == intent.id { pageStartID = nil }
        }
    }

    /// The page's `.start` / `.startNext` effect: the slot's start, launched once. Nil when
    /// there is none (the effect came from a tap that did not go through `tapStart`).
    func takeLaunch(_ kind: ShowerStartIntent.Kind) -> ShowerStartIntent? {
        guard let slot = startSlot, slot.phase == .starting, !slot.launched, slot.kind == kind else { return nil }
        startSlot?.launched = true
        return startSlot
    }

    /// The task of a launched start ended: only its own traces are cleared.
    func startEnded(_ id: UUID, returned: ShowerPageEvent) {
        if startTaskID == id { startTask = nil; startTaskID = nil }
        if pageStartID == id { pageStartID = nil; pageEvent(returned) }
        if startSlot?.id == id { startSlot = nil }
    }

    /// 好，开始: the system alert, once for this start.
    func confirmExplainer(_ id: UUID) {
        guard let slot = startSlot, slot.id == id, slot.phase == .awaitingConfirm else { return }
        if slot.demo { startSlot = nil; return }
        // Taken back since (or refused for the balance now): nothing is asked.
        guard slot.permit.isOpen, !balanceBlocks else { startSlot = nil; return }
        startSlot?.phase = .awaitingPermission
        let access = bluetoothAccess
        let permit = slot.permit
        permissionTask = Task { [weak self] in
            // Taken back before the request went: the system is not asked.
            guard permit.isOpen else { self?.permissionReturned(id, .notDetermined); return }
            let answer = await access.request()
            self?.permissionReturned(id, answer)
        }
    }

    /// 等会儿 (or the sheet swiped down) before 好，开始: nothing was created or asked.
    func cancelExplainer(_ id: UUID) {
        guard startSlot?.id == id, startSlot?.phase == .awaitingConfirm else { return }
        startSlot = nil
    }

    /// The system alert was answered. Only the start that asked, still waiting, still this
    /// account's and dorm's, goes on; any other answer is dropped.
    func permissionReturned(_ id: UUID, _ result: BluetoothAuthorization) {
        guard let slot = startSlot, slot.id == id, slot.phase == .awaitingPermission else { return }
        permissionTask = nil
        guard stillHolds(slot) else { startSlot = nil; return }
        switch result {
        case .allowed:
            launch(slot)
        case .denied:
            startSlot = nil
            pageEvent(.checkFailed(.noPermission))
        case .notDetermined:
            startSlot = nil
        }
    }

    /// The tap's account, dorm and moment still hold: nothing took it back since.
    func stillHolds(_ intent: ShowerStartIntent) -> Bool {
        intent.generation == startGeneration && intent.permit.isOpen && intent.binding.sameIdentity(binding)
    }

    /// Takes back every start tapped so far (退出登录, an account switch, another dorm, the app
    /// sent to the background): one waiting never runs; one running sends no authorize request
    /// from here on (its permit), and one whose request left ends as it would have.
    func invalidateStarts() {
        startGeneration += 1
        startSlot?.permit.revoke()
        startSlot = nil
        permissionTask?.cancel()
        permissionTask = nil
        // A first check still reading the number: its "sent" mark is no longer the request
        // leaving (the permit may refuse it), so the page waits for what really follows.
        pageEvent(.firstCheckWithdrawn)
    }

    func sceneChanged(_ scene: ShowerScene) {
        switch scene {
        case .background:
            invalidateStarts()
        case .inactive:
            // The system alert: the start waits for its answer.
            break
        case .active:
            // Back from Settings: a stale 「没有蓝牙权限」 goes; nothing starts by itself.
            if page.checkFailure == .noPermission, bluetoothAccess.authorization != .denied { pageEvent(.checkLineCleared) }
        }
    }

    /// A first check whose number matched marks the binding (`ShowerBinding.matchedAt`), only
    /// while it is still the tap's: an answer that came back to another account writes nothing.
    func markMatched(_ intent: ShowerStartIntent, _ result: ShowerState) {
        guard result.authorizeSent || [ShowerPhase.writePending, .running, .closing, .settling, .done].contains(result.phase) else { return }
        markMatched(intent.binding, generation:intent.generation)
    }

    /// The number read from the controller was this binding's (a start, or the manual 核对):
    /// marked, only while nothing took the binding back since (`startGeneration`).
    func markMatched(_ checked: ShowerBinding, generation: Int) {
        guard generation == startGeneration,
              var stored = (try? showerVault.binding()) ?? nil, stored.sameIdentity(checked),
              stored.matchedAt == nil else { return }
        stored.matchedAt = Date()
        guard (try? showerVault.saveBinding(stored)) != nil else { return }
        setBinding(stored)
    }

    /// Siri and Shortcuts: never explains, never asks for Bluetooth.
    func startFromShortcut(clear: Bool) async throws -> ShowerActionOutcome {
        if startSlot != nil { throw ShowerActionFailure(.busy) }
        // The balance before Bluetooth: nothing to ask or explain for a start that can't go.
        if let text = balanceRefusal(clear:clear) { throw ShowerActionFailure(text) }
        switch bluetoothAccess.authorization {
        case .notDetermined: throw ShowerActionFailure(FirstCheckText.shortcutNeverAsked(clear:clear))
        case .denied: throw ShowerActionFailure(FirstCheckFailure.noPermission.text(clear:clear))
        case .allowed: break
        }
        guard let binding else { return try await run(nil, start:true) }
        let intent = ShowerStartIntent(entry:.shortcut, kind:state.showerOver ? .next : .start, binding:binding,
                                       generation:startGeneration, firstCheck:binding.matchedAt == nil, phase:.starting,
                                       showingPage:false)
        startSlot = intent
        startSlot?.launched = true
        defer { if startSlot?.id == intent.id { startSlot = nil } }
        return try await run(intent, start:true)
    }
}

#if DEBUG
extension ShowerModel {
    /// campusdaily://demo/sh-detail-first-<explainer|checking|fail-<reason>> and sh-first-passed:
    /// the first check's faces over the demo dorm (no engine; nothing connects or asks).
    func demoFirstCheck(_ name: String?) {
        if startSlot?.demo == true { startSlot = nil }
        checkToastShown = false
        guard let name else { return }
        if name == "sh-first-passed" { checkToastShown = true; page.afterCheck = true; return }
        let prefix = "sh-detail-first-"
        guard name.hasPrefix(prefix) else { return }
        let state = String(name.dropFirst(prefix.count))
        switch state {
        case "explainer":
            var intent = ShowerStartIntent(entry:.page, kind:.start,
                                           binding:ShowerBinding(studentId:"demo", schoolId:"demo", machineId:"11223344",
                                                                 roomId:"demo", roomLabel:"demo"),
                                           generation:startGeneration, firstCheck:true, phase:.awaitingConfirm, showingPage:false)
            intent.demo = true
            startSlot = intent
        case "checking":
            page.firstCheck = true
            page.starting = true
        case _ where state.hasPrefix("fail-"):
            page.checkFailure = FirstCheckFailure(rawValue:String(state.dropFirst(5)))
        default: break
        }
    }
}
#endif
