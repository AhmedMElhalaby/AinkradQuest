import SwiftUI
import AinkradAppKit

/// Placeholder for Task 11. Single-project timeline.
struct TimelineSurface: View {
    let document: ProjectDocument
    let theme: HostTheme

    var body: some View {
        Text("Timeline")
            .foregroundStyle(theme.tokens.foreground)
    }
}
