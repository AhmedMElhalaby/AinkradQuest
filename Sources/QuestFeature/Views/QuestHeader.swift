import SwiftUI
import AinkradAppKit

/// The shell's top bar: where you are, which surface, search, and the three
/// global actions.
struct QuestHeader: View {
    let trail: [String]
    @Binding var surface: QuestSurface
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let showsSwitcher: Bool
    /// The gear acts on the selected project, so it is withheld — not merely
    /// inert — when there is none.
    let showsSettings: Bool
    let onNew: () -> Void
    let onSettings: () -> Void
    let onTrash: () -> Void

    var body: some View {
        VStack(spacing: AinkradSpacing.sm) {
            HStack(spacing: AinkradSpacing.md) {
                AinkradBreadcrumb(items: trail)
                Spacer(minLength: AinkradSpacing.md)
                AinkradSearchField(text: $searchText, placeholder: "Search items",
                                   focus: searchFocused)
                    .frame(maxWidth: 280)
                // The no-`size` initializer, so the button frame comes from the
                // kit's own default rather than a literal here. That overload
                // takes no `tooltip:`, so the hover hint and its VoiceOver
                // equivalent are attached explicitly — `.help` alone is
                // mouse-only, and these three buttons are icon-only.
                iconAction("plus", "New", onNew)
                if showsSettings {
                    iconAction("gearshape", "Project settings", onSettings)
                        .transition(.opacity)
                }
                iconAction("trash", "Trash", onTrash)
            }

            if showsSwitcher {
                AinkradSegmentedPicker(items: SurfaceVisibility.offered(hasProject: true),
                                       selection: $surface) { $0.title }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .animation(AinkradMotion.present, value: showsSwitcher)
        .animation(AinkradMotion.present, value: showsSettings)
    }

    private func iconAction(_ systemName: String, _ label: String,
                            _ action: @escaping () -> Void) -> some View {
        AinkradIconButton(systemName: systemName, action: action)
            .help(label)
            .accessibilityLabel(label)
    }
}
