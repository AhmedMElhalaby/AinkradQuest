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
/// itself; the per-folder picker on project creation remains the way to
/// attach a folder outside any granted root.
struct QuestSettingsView: View {
    let presentation: any PluginPresentationControl
    let documents: PluginDocumentStore

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @State private var mode: PluginPresentation
    @State private var projectsRoot: URL?
    @State private var vaultRoot: URL?
    @State private var error: String?

    init(presentation: any PluginPresentationControl, documents: PluginDocumentStore) {
        self.presentation = presentation
        self.documents = documents
        _mode = State(initialValue: presentation.current)
        _projectsRoot = State(initialValue: FolderBookmark.resolve(
            forKey: FolderBookmark.projectsRootKey, in: documents))
        _vaultRoot = State(initialValue: FolderBookmark.resolve(
            forKey: FolderBookmark.vaultRootKey, in: documents))
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
                    Text("These folders are used only to suggest attachments when a project is created — nothing is read or written otherwise, and you can always attach a folder from outside them.")
                        .font(AinkradFontResolver.font(.body, typography: typo))
                        .foregroundStyle(theme.foreground)

                    rootRow(title: "Projects folder",
                           help: "Suggests a matching repo or folder by name when you create a project.",
                           root: $projectsRoot, key: FolderBookmark.projectsRootKey)

                    rootRow(title: "Vault folder",
                           help: "Suggests a matching vault folder by name when you create a project.",
                           root: $vaultRoot, key: FolderBookmark.vaultRootKey)

                    if let error {
                        Text(error).font(.caption).foregroundStyle(statusColors.danger)
                    }
                }
            }
        }
        .padding()
        .onChange(of: mode) { _, newValue in presentation.set(newValue) }
    }

    private func rootRow(title: String, help: String, root: Binding<URL?>,
                         key: String) -> some View {
        AinkradFormRow(title: title, help: help) {
            HStack(spacing: AinkradSpacing.sm) {
                Text(root.wrappedValue?.path ?? "Not set")
                    .font(AinkradFontResolver.font(.mono, typography: typo))
                    .foregroundStyle(theme.foreground.opacity(0.8))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AinkradButton(title: "Choose…", style: .secondary) { pickRoot(root, key: key) }
                if root.wrappedValue != nil {
                    AinkradButton(title: "Clear", style: .ghost) { clearRoot(root, key: key) }
                }
            }
        }
    }

    private func pickRoot(_ root: Binding<URL?>, key: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FolderBookmark.save(url, forKey: key, in: documents)
            root.wrappedValue = url
            error = nil
        } catch {
            self.error = "Could not save that folder: \(error.localizedDescription)"
        }
    }

    private func clearRoot(_ root: Binding<URL?>, key: String) {
        FolderBookmark.clear(forKey: key, in: documents)
        root.wrappedValue = nil
    }
}
