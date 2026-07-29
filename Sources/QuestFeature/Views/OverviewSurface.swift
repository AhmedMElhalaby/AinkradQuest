import SwiftUI
import AinkradAppKit

/// Placeholder for Task 11. Single-project overview.
struct OverviewSurface: View {
    let store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    var body: some View {
        Text("Overview")
            .foregroundStyle(theme.tokens.foreground)
    }
}
