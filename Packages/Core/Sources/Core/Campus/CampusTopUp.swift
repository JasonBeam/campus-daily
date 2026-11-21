//
//  CampusTopUp.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/05.
//

import Foundation

/// 校园充值: the school's own top-up in WeChat. The app never handles money: it copies the name of
/// the school's WeChat service (「e广工商大办事大厅」), opens WeChat, where the user finds the
/// service by pulling down the chat list (or pastes the name into the search), and reads the
/// balances again once the user comes back.
///
/// WeChat's ticket links for the service work for one user only (the next person is told the
/// link was already used), so the app holds none and opens plain WeChat.
public enum CampusTopUp {
    /// What goes on the pasteboard before WeChat opens.
    public static let serviceName = "e广工商大办事大厅"
    /// Plain WeChat, no ticket.
    public static let weChat = URL(string: "weixin://")!
}
