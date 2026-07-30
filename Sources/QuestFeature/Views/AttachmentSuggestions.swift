import SwiftUI
import AppKit
import AinkradAppKit

/// A folder found under a granted root whose name matches the new project's
/// name. Never authoritative — the sheet that shows these starts every
/// checkbox unchecked, because a wrong suggestion silently accepted is worse
/// than no suggestion at all.
struct AttachmentSuggestion: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let scheme: LinkScheme
    var label: String { url.lastPathComponent }
}

enum AttachmentSuggestions {
    /// Suggestions for a newly created project. Empty when no root is granted —
    /// that is the normal state, not an error, and the per-folder picker remains
    /// available regardless.
    static func build(projectName: String, projectsRoot: URL?,
                      vaultRoot: URL?) -> [AttachmentSuggestion] {
        var found: [AttachmentSuggestion] = []
        if let projectsRoot {
            found += FolderMatch.candidates(for: projectName, in: projectsRoot)
                .map { AttachmentSuggestion(url: $0, scheme: FolderMatch.linkKind(for: $0)) }
        }
        if let vaultRoot {
            found += FolderMatch.candidates(for: projectName, in: vaultRoot)
                .map { AttachmentSuggestion(url: $0, scheme: .folder) }
        }
        return found
    }
}

/// Shown after a project is created when `AttachmentSuggestions.build`
/// returned at least one candidate. Every suggestion starts unchecked — the
/// user opts in, never the other way round. "Attach another folder…" is the
/// escape hatch for anything outside a granted root, and works with no root
/// granted at all: it goes straight to `NSOpenPanel`.
struct AttachmentPicker: View {
    @Bindable var store: ProjectStore
    let projectID: UUID
    let suggestions: [AttachmentSuggestion]
    let documents: PluginDocumentStore
    let theme: HostTheme
    /// Called once the sheet is dismissed, whether or not anything was attached.
    let onDone: () -> Void

    @Environment(\.ainkradTypography) private var typo
    @State private var checked: Set<String> = []
    @State private var error: String?

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                Text("Folders that look like they belong to this project. Nothing is attached until you say so.")
                    .font(AinkradFontResolver.font(.body, typography: typo))
                    .foregroundStyle(theme.tokens.foreground)

                ForEach(suggestions) { suggestion in
                    Toggle(isOn: isChecked(suggestion)) {
                        Label(suggestion.label, systemImage: LinkSymbol.name(for: suggestion.scheme))
                    }
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
                }

                HStack {
                    AinkradButton(title: "Attach another folder…", style: .ghost, action: attachAnother)
                    Spacer()
                    AinkradButton(title: "Skip", style: .ghost, action: onDone)
                    AinkradButton(title: "Attach selected", style: .primary, action: attachChecked)
                }
            }
        }
        .padding()
        .environment(\.ainkradTheme, theme.tokens)
    }

    private func isChecked(_ suggestion: AttachmentSuggestion) -> Binding<Bool> {
        Binding(
            get: { checked.contains(suggestion.id) },
            set: { isOn in
                if isOn { checked.insert(suggestion.id) } else { checked.remove(suggestion.id) }
            })
    }

    private func attachChecked() {
        for suggestion in suggestions where checked.contains(suggestion.id) {
            guard attach(url: suggestion.url, scheme: suggestion.scheme) else { return }
        }
        onDone()
    }

    /// Opens an `NSOpenPanel` regardless of any granted root — the per-folder
    /// picker is the escape hatch for anything outside one, so it must not
    /// depend on a root being set.
    private func attachAnother() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = attach(url: url, scheme: FolderMatch.linkKind(for: url))
    }

    /// Builds the link through `LinkValidation.normalize` so an attachment
    /// never bypasses the same rules a manual link add would go through, then
    /// saves a per-attachment bookmark so the folder stays reachable later.
    @discardableResult
    private func attach(url: URL, scheme: LinkScheme) -> Bool {
        let outcome = LinkValidation.normalize(scheme: scheme, identifier: url.path,
                                               label: url.lastPathComponent, repo: nil)
        switch outcome {
        case .invalid(let message):
            error = message
            return false
        case .valid(let link):
            do {
                try store.addLink(to: .project(projectID), link: link, actor: .user)
                try FolderBookmark.save(url, forKey: FolderBookmark.attachmentKey(UUID()),
                                        in: documents)
                error = nil
                return true
            } catch let failure as QuestError {
                error = failure.message
                return false
            } catch {
                self.error = error.localizedDescription
                return false
            }
        }
    }
}
