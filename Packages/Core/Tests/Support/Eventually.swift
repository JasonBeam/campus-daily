import XCTest

/// Polls `condition` every 5 ms until it holds. After `seconds` (2 by default) the test fails
/// instead of waiting forever; returns whether the condition held.
@discardableResult
public func eventually(seconds: Double = 2, _ condition: @Sendable () async -> Bool,
                       file: StaticString = #filePath, line: UInt = #line) async -> Bool {
    for _ in 0..<max(1, Int(seconds * 200)) {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    if await condition() { return true }
    XCTFail("condition never held", file: file, line: line)
    return false
}
