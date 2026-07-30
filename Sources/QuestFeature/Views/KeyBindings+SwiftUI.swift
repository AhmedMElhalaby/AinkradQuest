import SwiftUI

/// Bridges the Foundation-only binding table to SwiftUI. Lives beside the
/// views, not in Logic, so `KeyBindings` stays free of SwiftUI and testable.
extension KeyBindings.Modifiers {
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.option) { result.insert(.option) }
        return result
    }
}
