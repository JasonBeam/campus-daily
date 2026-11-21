//
//  SchoolLoginNavigation.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// WKWebView navigation allow-list for the school login page (the page and every frame in it):
/// https on the three school hosts, default port, no user info. A frame may also be
/// `about:blank` / `about:srcdoc`, which loads nothing. Everything else is cancelled.
public enum SchoolLoginNavigation {
    static let schoolHosts: Set<String> = [SchoolEndpoints.ecyktHost, SchoolEndpoints.portalHost, SchoolEndpoints.casHost]

    public static func allows(_ url: URL, isMainFrame: Bool) -> Bool {
        if !isMainFrame, url.scheme?.lowercased() == "about", ["about:blank", "about:srcdoc"].contains(url.absoluteString) { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              schoolHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return true
    }
}
