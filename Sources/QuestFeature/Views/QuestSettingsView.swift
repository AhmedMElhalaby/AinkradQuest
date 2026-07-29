import SwiftUI
import AinkradAppKit

/// Quest's settings surface — a "Presentation" (pane/overlay) control on the
/// Cardinal HUD kit, mirroring `LeylineSettingsView`. Backed by
/// `HostServices.presentation` (`PluginPresentationControl`): the override
/// takes effect the next time Quest is opened, never morphing an
/// already-open window.
struct QuestSettingsView: View {
    let presentation: any PluginPresentationControl

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @State private var mode: PluginPresentation

    init(presentation: any PluginPresentationControl) {
        self.presentation = presentation
        _mode = State(initialValue: presentation.current)
    }

    var body: some View {
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
        .padding()
        .onChange(of: mode) { _, newValue in presentation.set(newValue) }
    }
}
