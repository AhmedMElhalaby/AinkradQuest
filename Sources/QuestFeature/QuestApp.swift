import SwiftUI
import AinkradAppKit

public struct QuestApp: AinkradApp {
    public static let id = "quest"
    public static let displayName = "Quest"
    public static let icon = "checklist"

    /// Keyed by the host-minted instance id rather than
    /// `ObjectIdentifier(host)` — an address of a box around a non-class-bound
    /// existential, reusable after free, and never evicted. See
    /// `PluginInstanceStorage`.
    @MainActor private static let stores = PluginInstanceStorage<ProjectStore>()

    /// The instance key for `host`.
    ///
    /// A generation-8 host mints one. A generation-7 host does not implement
    /// `PluginInstanceIdentity`, so fall back to the OLD per-host object
    /// identity rather than to one shared id — collapsing every legacy host
    /// onto a single key would make two hosts share a store, which is a
    /// regression rather than a fallback. The address-reuse hazard stays only
    /// on the legacy path, exactly as before, and is gone on generation 8.
    @MainActor private static func instance(of host: HostServices) -> PluginInstanceID {
        if let identified = host as? PluginInstanceIdentity { return identified.instanceID }
        let key = ObjectIdentifier(host as AnyObject)
        if let existing = legacyIDs[key] { return existing }
        let minted = PluginInstanceID()
        legacyIDs[key] = minted
        return minted
    }
    @MainActor private static var legacyIDs: [ObjectIdentifier: PluginInstanceID] = [:]

    @MainActor private static func store(for host: HostServices) -> ProjectStore {
        stores.value(for: instance(of: host)) {
            ProjectStore(repository: DocumentProjectRepository(documents: host.documents))
        }
    }

    public static func makeRootView(host: HostServices) -> AnyView {
        AnyView(QuestRootView(store: store(for: host), theme: host.theme))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(QuestSettingsView(presentation: host.presentation))
    }

    public static func chromeFill(host: HostServices) -> Color? {
        host.theme.tokens.background
    }
}

/// Generation 8: release a closed instance's store rather than let it linger
/// (and its cached documents with it) for the rest of the process.
extension QuestApp: AinkradAppTeardown {
    public static func teardown(instance: PluginInstanceID) {
        stores.remove(instance)
        // `mcpServers` is added in Task 12; until then, teardown removes only
        // `stores`.
    }
}
