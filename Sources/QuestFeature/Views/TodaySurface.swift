import SwiftUI
import AinkradAppKit

/// Placeholder for Task 11. Cross-project inbox view.
struct TodaySurface: View {
    let store: ProjectStore
    let theme: HostTheme
    let onOpen: (WorkItem) -> Void

    var body: some View {
        Text("Today")
            .foregroundStyle(theme.tokens.foreground)
    }
}
