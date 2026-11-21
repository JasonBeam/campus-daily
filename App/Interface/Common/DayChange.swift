//
//  DayChange.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import Combine
import Foundation
import UIKit

/// The day turned (midnight) or the clock or time zone moved: words like 今天 and 昨天 drawn
/// before it are out of date. The system posts these while the app runs, and on coming back
/// to the foreground when it happened meanwhile.
enum DayChange {
    static let names: [Notification.Name] = [.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification]

    /// On the main queue (`NSCalendarDayChanged` may come on any thread).
    static var publisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(names.map { NotificationCenter.default.publisher(for:$0) })
            .map { _ in () }
            .receive(on:DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
