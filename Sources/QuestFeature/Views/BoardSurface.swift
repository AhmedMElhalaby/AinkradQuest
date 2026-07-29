import SwiftUI
import AinkradAppKit

/// Placeholder for Task 11. Single-project board.
struct BoardSurface: View {
    let store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    var body: some View {
        Text("Board")
            .foregroundStyle(theme.tokens.foreground)
    }
}
