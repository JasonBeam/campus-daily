import Foundation
import UserNotifications
import CryptoKit
import WaterCore

/// Only consumes successfully refreshed orders; it never initiates a transaction.
@MainActor final class LaundryReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LaundryReminders()
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let notificationID = "campus.laundry.end"
    var enabled: Bool { defaults.bool(forKey:"laundry.reminders.enabled") }
    var status: String { defaults.string(forKey:"laundry.reminders.status") ?? "尚未安排订单提醒。启动洗衣后返回校日常更新订单。" }
    private func status(_ text: String) { if status != text { defaults.set(text,forKey:"laundry.reminders.status") } }
    private var completedKeys: [String] { defaults.stringArray(forKey:"laundry.reminders.completed") ?? [] }
    private func markDelivered(_ key: String, at date: Date) {
        let dates = (defaults.dictionary(forKey:"laundry.reminders.deliveryDates") ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        let ledger = LaundryReminderPolicy.recordDeliveryTime(date.timeIntervalSince1970,for:key,keys:completedKeys,dates:dates)
        defaults.set(ledger.keys,forKey:"laundry.reminders.completed")
        defaults.set(ledger.dates,forKey:"laundry.reminders.deliveryDates")
    }
    override private init() { super.init(); center.delegate = self }
    func setEnabled(_ value: Bool) async throws -> Bool {
        if value {
            guard try await center.requestAuthorization(options:[.alert,.sound]) else { return false }
        }
        defaults.set(value,forKey:"laundry.reminders.enabled")
        if !value { clear(); status("洗衣结束提醒已关闭。") }
        return true
    }
    private func clear() {
        center.removePendingNotificationRequests(withIdentifiers:[notificationID])
        defaults.removeObject(forKey:"laundry.reminders.order")
        defaults.removeObject(forKey:"laundry.reminders.due")
    }
    func update(_ record: LaundryCheckoutRecord) async throws {
        guard enabled, let order = record.order, let owner = record.credentialIdentity,
              record.orderId == order.id, record.deviceId == order.deviceId,
              let observed = record.orderUpdatedAt, abs(observed.timeIntervalSinceNow) < 60 else { return }
        let key = SHA256.hash(data:Data((owner + ":" + order.id).utf8)).map { String(format:"%02x",$0) }.joined()
        let tracked = defaults.string(forKey:"laundry.reminders.order")
        if tracked != nil && tracked != key { clear() }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        guard enabled else { return }
        let estimateStillPending = pending.contains { $0.identifier == notificationID }
        if let deliveredForOrder = delivered.first(where: { $0.request.content.userInfo["orderKey"] as? String == key }) {
            markDelivered(key,at:deliveredForOrder.date)
        }
        let alreadyAlerted = completedKeys.contains(key)
        let now = Date()
        let action = LaundryReminderPolicy.action(status:order.status.text,remaining:order.remainTime,
            observedAt:observed.timeIntervalSince1970,now:now.timeIntervalSince1970,tracked:tracked == key,
            alreadyReminded:alreadyAlerted,deadline:record.countdownDeadline?.timeIntervalSince1970)
        switch action {
        case .clear:
            clear()
            status("订单已取消或启动失败，已撤销倒计时提醒。")
            return
        case .ignore:
            if order.status.text == "50", alreadyAlerted { status("这笔订单已安排过结束提醒。") }
            else if order.running, order.remainTime == nil { status("尚未获取到倒计时，请刷新订单以安排提醒。") }
            else if order.status.text == "50", tracked != key { status("本次未获取到洗衣倒计时，未安排提醒。") }
            return
        case .estimate: break
        }
        guard case .estimate(let due) = action else { return }
        if tracked == key, estimateStillPending, abs(defaults.double(forKey:"laundry.reminders.due") - due) < 2 { return }
        try await send("洗衣倒计时结束",body:"设定的洗衣时间已到，请及时查看机器并取衣。",after:max(1,due-Date().timeIntervalSince1970),orderKey:key)
        guard enabled else { clear(); return }
        defaults.set(key,forKey:"laundry.reminders.order")
        defaults.set(due,forKey:"laundry.reminders.due")
        status("已安排倒计时提醒，预计 " + Date(timeIntervalSince1970:due).formatted(date:.omitted,time:.shortened) + " 提醒取衣。")
    }
    private func send(_ title: String, body: String, after: TimeInterval, identifier: String = "campus.laundry.end", orderKey: String? = nil) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            status("系统通知未允许，请在 iPhone 设置中打开校日常通知。")
            throw ReminderError.notAuthorized
        }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        if let orderKey { content.userInfo = ["orderKey":orderKey] }
        try await center.add(UNNotificationRequest(identifier:identifier,content:content,
            trigger:UNTimeIntervalNotificationTrigger(timeInterval:after,repeats:false)))
    }
    func test() async throws -> Bool {
        guard try await center.requestAuthorization(options:[.alert,.sound]) else { return false }
        try await send("校日常测试提醒",body:"这是倒计时通知测试。洗衣时间到后也会通过系统通知提醒。",
                       after:10,identifier:"campus.laundry.test")
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let orderKey = notification.request.content.userInfo["orderKey"] as? String
        if notification.request.identifier == "campus.laundry.end", let orderKey {
            let date = notification.date
            await MainActor.run { LaundryReminders.shared.markDelivered(orderKey,at:date) }
        }
        return [.banner,.list,.sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let orderKey = request.content.userInfo["orderKey"] as? String
        if request.identifier == "campus.laundry.end", let orderKey {
            let date = response.notification.date
            await MainActor.run { LaundryReminders.shared.markDelivered(orderKey,at:date) }
        }
    }
}

private enum ReminderError: Error { case notAuthorized }
