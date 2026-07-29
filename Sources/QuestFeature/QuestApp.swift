import SwiftUI
import AinkradAppKit

public struct QuestApp: AinkradApp {
    public static let id = "quest"
    public static let displayName = "Quest"
    public static let icon = "checklist"

    public static func makeRootView(host: HostServices) -> AnyView {
        AnyView(Text("Quest").foregroundStyle(host.theme.tokens.foreground))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(EmptyView())
    }

    public static func chromeFill(host: HostServices) -> Color? {
        host.theme.tokens.background
    }
}
