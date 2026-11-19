import Foundation

/// How same-named places are told apart in a list: each row is titled by the first level of
/// its location (校区 · 公寓 · 楼栋 · 房间) that differs among the candidates, with the full
/// location under it.
public enum LocationNaming {
    /// One title per path, in order. Paths are the location levels, top first. When no level
    /// differs (or there is one path), the last level is the title.
    public static func titles(_ paths: [[String]]) -> [String] {
        let depth = paths.map(\.count).max() ?? 0
        let level = (0..<depth).first { index in
            Set(paths.map { index < $0.count ? $0[index] : "" }).count > 1
        }
        return paths.map { path in
            if let level, level < path.count { return path[level] }
            return path.last ?? ""
        }
    }

    /// Titles for locations written 「北校区 · 东苑公寓 · 3 栋 · 108」.
    public static func titles(locations: [String]) -> [String] {
        titles(locations.map { $0.components(separatedBy: " · ") })
    }

    /// Above a same-name list: 「学校有 2 间都叫 3 栋 108，选你住的那间。」.
    public static func sameNameHint(count: Int, name: String) -> String {
        "学校有 \(count) 间都叫 \(name)，选你住的那间。"
    }
}
