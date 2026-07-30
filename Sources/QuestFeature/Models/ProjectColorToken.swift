import Foundation

/// The colour choices a project or a status may carry.
///
/// THEME TOKEN NAMES, never raw colours: the host owns the palette, so a
/// project that stored `#FF0000` would be unreadable in one of the themes and
/// would not follow a theme change. The set is closed because `colorToken` is a
/// free-form `String` on `Project` and `Status` — an unresolvable name would
/// render as nothing.
///
/// It lives in `Models/` rather than beside the picker that started it because
/// it is the vocabulary of a persisted field, and BOTH write paths must hold to
/// it. The UI could only ever offer these six; the MCP tool accepted any string,
/// so an agent-written `"banana"` persisted, rendered as a fallback, and was
/// silently rewritten to `accentPrimary` the next time the editor opened — which
/// the next plan then reported as a recolour the user never made. The MCP layer
/// must not import a `Views` type to close that gap, so the enum moved down.
/// The theme lookup (`color(in:)`) stays in the view layer, where `HostTheme` is.
enum ProjectColorToken: String, CaseIterable, Identifiable {
    case accentPrimary, accentSecondary, success, warning, danger, muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accentPrimary: "Accent"
        case .accentSecondary: "Secondary"
        case .success: "Green"
        case .warning: "Amber"
        case .danger: "Red"
        case .muted: "Grey"
        }
    }

    /// Maps whatever a project currently stores onto the closed set. Projects
    /// created before this control existed hold the default `"accent"`, and a
    /// document could carry anything; both land on `.accentPrimary` rather than
    /// leaving the picker with no selection.
    static func resolve(_ token: String) -> ProjectColorToken {
        ProjectColorToken(rawValue: token) ?? .accentPrimary
    }

    /// Every valid value, for error messages that tell the caller what to send.
    static var validNames: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}
