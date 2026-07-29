import SwiftUI
import AinkradAppKit

/// Placeholder for Task 11. Single-project item list.
struct ListSurface: View {
    let store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    var body: some View {
        Text("List")
            .foregroundStyle(theme.tokens.foreground)
    }
}
