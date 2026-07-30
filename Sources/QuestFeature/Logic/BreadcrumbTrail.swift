import Foundation

/// The header trail. Pure so crumb assembly is not re-derived inline in the
/// header body, and so "cross-project surface must not name a project" is a
/// tested rule rather than an accident of view layout.
public enum BreadcrumbTrail {
    public static func items(projectName: String?,
                             surface: QuestSurface,
                             sheet: String?) -> [String] {
        var trail = ["Quest"]
        // Only a project-scoped surface names a project. Today is an inbox
        // across every active project; naming one there would be a lie.
        if surface.requiresProject,
           let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            trail.append(name)
        }
        trail.append(surface.title)
        if let sheet, !sheet.isEmpty { trail.append(sheet) }
        return trail
    }
}
