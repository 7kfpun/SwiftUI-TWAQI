import Foundation
import os

/// Diagnostics for failures that are handled silently. Messages never carry
/// tokens, ids or request bodies; interpolated errors stay private (redacted
/// outside a debugger) by `os.Logger`'s default.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TWAQI"

    static let push = Logger(subsystem: subsystem, category: "push")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let app = Logger(subsystem: subsystem, category: "app")
}
