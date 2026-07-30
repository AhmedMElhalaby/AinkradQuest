import SwiftUI
import AppKit
import AinkradAppKit

/// Quest's settings surface — a "Presentation" (pane/overlay) control on the
/// Cardinal HUD kit, mirroring `LeylineSettingsView`. Backed by
/// `HostServices.presentation` (`PluginPresentationControl`): the override
/// takes effect the next time Quest is opened, never morphing an
/// already-open window.
///
/// Also hosts the two root grants (`FolderBookmark.projectsRootKey` /
/// `vaultRootKey`) that drive automatic attachment suggestions at project
/// creation time — and ONLY that. Granting a root does not attach anything by
/// itself; a project's Overview always has its own "Attach folder…" button
/// (`FolderAttachButton`), independent of these grants.
struct QuestSettingsView: View {
    let presentation: any PluginPresentationControl
    let documents: PluginDocumentStore

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @State private var mode: PluginPresentation
    /// Bumped whenever a grant is changed, to re-read `FolderBookmark.grant`.
    /// The grants themselves are NOT cached in `@State` seeded from `init`:
    /// this initializer re-runs on every parent re-render, and anything it
    /// called would run with it.
    @State private var grantRevision = 0
    @State private var error: String?

    init(presentation: any PluginPresentationControl, documents: PluginDocumentStore) {
        self.presentation = presentation
        self.documents = documents
        _mode = State(initialValue: presentation.current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradCard {
                VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                    Text("Quest tracks projects and work items per workspace.")
                        .font(AinkradFontResolver.font(.body, typography: typo))
                        .foregroundStyle(theme.foreground)

                    AinkradFormRow(title: "Presentation", help: "Applies the next time Quest opens.") {
                        AinkradSegmentedPicker(items: [PluginPresentation.pane, .overlay], selection: $mode) {
                            $0 == .pane ? "Pane" : "Overlay"
                        }
                    }
                }
            }

            AinkradCard {
                VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                    Text("These folders are used only to suggest attachments when a project is created — nothing is read or written otherwise. Every project's Overview also has its own Attach folder… button, which works whether or not you set anything here.")
                        .font(AinkradFontResolver.font(.body, typography: typo))
                        .foregroundStyle(theme.foreground)

                    rootRow(title: "Projects folder",
                           help: "Suggests a matching repo or folder by name when you create a project.",
                           key: FolderBookmark.projectsRootKey)

                    rootRow(title: "Vault folder",
                           help: "Suggests a matching vault folder by name when you create a project.",
                           key: FolderBookmark.vaultRootKey)

                    if let error {
                        Text(error).font(.caption).foregroundStyle(statusColors.danger)
                    }
                }
            }
        }
        .padding()
        .onChange(of: mode) { _, newValue in presentation.set(newValue) }
    }

    /// Rendering this row must never acquire a scoped resource — it reads
    /// `FolderBookmark.grant`, which resolves for display only. `grantRevision`
    /// is read so SwiftUI re-runs the row after Choose…/Clear.
    private func rootRow(title: String, help: String, key: String) -> some View {
        _ = grantRevision
        let grant = FolderBookmark.grant(forKey: key, in: documents)
        return AinkradFormRow(title: title, help: help) {
            HStack(spacing: AinkradSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.pathText(grant))
                        .font(AinkradFontResolver.font(.mono, typography: typo))
                        .foregroundStyle(theme.foreground.opacity(0.8))
                        .lineLimit(1).truncationMode(.middle)
                    // A grant that no longer resolves is NOT the same as no
                    // grant: without this the user sees "Not set", cannot tell
                    // why suggestions stopped, and (previously) had no Clear
                    // button to fix it.
                    if case .unresolvable = grant {
                        Text("This folder can no longer be found — it was moved, renamed, or deleted. Choose it again, or clear it.")
                            .font(.caption)
                            .foregroundStyle(statusColors.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AinkradButton(title: "Choose…", style: .secondary) { pickRoot(key: key) }
                // Available for a broken grant too, not just a working one.
                if grant != .notGranted {
                    AinkradButton(title: "Clear", style: .ghost) { clearRoot(key: key) }
                }
            }
        }
    }

    private static func pathText(_ grant: FolderBookmark.Grant) -> String {
        switch grant {
        case .notGranted: "Not set"
        case .granted(let path): path
        case .unresolvable(let path): path ?? "Previously granted folder"
        }
    }

    private func pickRoot(key: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FolderBookmark.save(url, forKey: key, in: documents)
            grantRevision += 1
            error = nil
        } catch {
            self.error = "Could not save that folder: \(error.localizedDescription)"
        }
    }

    private func clearRoot(key: String) {
        FolderBookmark.clear(forKey: key, in: documents)
        grantRevision += 1
    }
}
