import Core

public extension LiveShowerGate {
    /// A gate over a real shower record at rest (idle), as on a phone that has not showered.
    static func idleShower() -> LiveShowerGate { LiveShowerGate(record: { .known(.idle) }) }
}

public extension SampleMode {
    /// Sample mode over an idle real shower: 「先看看示例」 may open.
    static func overIdleShower() -> SampleMode { SampleMode(gate: .idleShower()) }
}
