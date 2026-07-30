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
    /// that is the normal state, not an error. The per-folder picker
    /// (`FolderAttachButton`, on Overview) does not depend on this and is
    /// reachable regardless of whether any suggestion ever fired.
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

/// The one place a folder actually becomes a `Link`, shared by the
/// suggestion sheet and the persistent Overview picker so the two cannot
/// drift on validation or bookmarking. Builds the link through
/// `LinkValidation.normalize` — never hand-constructed — and saves a
/// per-attachment bookmark under `FolderBookmark.attachmentKey` so the
/// folder stays reachable later. Returns a failure message, or `nil` on
/// success; never `try?`.
@MainActor
enum FolderAttachment {
    static func attach(url: URL, scheme: LinkScheme, to projectID: UUID,
                       store: ProjectStore, documents: PluginDocumentStore) -> String? {
        switch LinkValidation.normalize(scheme: scheme, identifier: url.path,
                                        label: url.lastPathComponent, repo: nil) {
        case .invalid(let message):
            return message
        case .valid(let link):
            do {
                try store.addLink(to: .project(projectID), link: link, actor: .user)
                try FolderBookmark.save(url, forKey: FolderBookmark.attachmentKey(UUID()),
                                        in: documents)
                return nil
            } catch let failure as QuestError {
                return failure.message
            } catch {
                return error.localizedDescription
            }
        }
    }
}

/// Shown after a project is created when `AttachmentSuggestions.build`
/// returned at least one candidate. Every suggestion starts unchecked — the
/// user opts in, never the other way round. "Attach another folder…" here is
/// a convenience alongside the suggestions, not the only way to reach the
/// picker — `FolderAttachButton` on Overview is the one that is always
/// reachable, independent of whether this sheet ever appears.
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

    /// Attempts every checked suggestion rather than stopping at the first
    /// failure — a checkbox the user ticked should not silently go
    /// unprocessed because an earlier one in the list failed. Failures are
    /// collected and reported together; the sheet only closes once nothing
    /// failed.
    private func attachChecked() {
        let toAttach = suggestions.filter { checked.contains($0.id) }
        var failures: [String] = []
        for suggestion in toAttach {
            if let message = FolderAttachment.attach(url: suggestion.url, scheme: suggestion.scheme,
                                                      to: projectID, store: store, documents: documents) {
                failures.append("\(suggestion.label): \(message)")
            }
        }
        if failures.isEmpty {
            error = nil
            onDone()
        } else {
            error = failures.joined(separator: "; ")
        }
    }

    /// Opens an `NSOpenPanel` regardless of any granted root — this is a
    /// convenience alongside the suggestions, and (like `FolderAttachButton`)
    /// must not depend on a root being set.
    private func attachAnother() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = FolderAttachment.attach(url: url, scheme: FolderMatch.linkKind(for: url),
                                        to: projectID, store: store, documents: documents)
    }
}

/// The escape hatch for attaching a folder to an EXISTING project,
/// independent of any root grant and independent of whether
/// `AttachmentSuggestions.build` ever found anything for this project. Lives
/// on Overview beside the links list (`LinkListView`/`LinkEditor`) so
/// attaching a folder is always reachable, not gated behind a suggestion
/// sheet that may never appear.
struct FolderAttachButton: View {
    @Bindable var store: ProjectStore
    let projectID: UUID
    let documents: PluginDocumentStore
    let theme: HostTheme

    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AinkradButton(title: "Attach folder…", style: .secondary, action: attach)
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
        }
    }

    private func attach() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = FolderAttachment.attach(url: url, scheme: FolderMatch.linkKind(for: url),
                                        to: projectID, store: store, documents: documents)
    }
}
