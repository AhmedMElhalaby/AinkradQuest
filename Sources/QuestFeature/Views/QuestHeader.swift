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
                AinkradIconButton(systemName: "plus", size: 16, tooltip: "New") { onNew() }
                AinkradIconButton(systemName: "gearshape", size: 16,
                                  tooltip: "Project settings") { onSettings() }
                AinkradIconButton(systemName: "trash", size: 16, tooltip: "Trash") { onTrash() }
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
    }
}
