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
        AnyView(QuestShell(store: store(for: host), theme: host.theme, documents: host.documents))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(QuestSettingsView(presentation: host.presentation, documents: host.documents))
    }

    public static func chromeFill(host: HostServices) -> Color? {
        host.theme.tokens.background
    }

    /// The per-host MCP server, created once and cached — the same shape as
    /// `stores`, keyed by the same instance id, because the server MUST read
    /// the store the window is showing. Building a fresh `ProjectStore` here
    /// would hand the assistant a detached second copy that reloads from disk
    /// and never sees a task the user just typed.
    @MainActor private static let mcpServers = PluginInstanceStorage<MCPAppServer>()

    @MainActor static func mcpServer(for host: HostServices) -> MCPAppServer {
        mcpServers.value(for: instance(of: host)) {
            let operations = QuestMCPOperations(store: store(for: host))
            let (server, failures) = QuestMCPServer.make(appID: id) { operation, arguments in
                await operations.run(operation: operation, arguments: arguments)
            }
            // A dropped tool is a silently missing capability — say so rather
            // than let the assistant just never see it.
            if !failures.isEmpty {
                host.log.error("Quest MCP: tools rejected — \(failures.joined(separator: ", "))")
            }
            return server
        }
    }
}

/// Publishes Quest's projects and work items to the host assistant. Cached
/// per host by `mcpServer(for:)`, so the assistant reads the same store the
/// window shows.
extension QuestApp: AinkradAppMCP {
    public static func makeMCPServer(host: HostServices) -> MCPAppServer { mcpServer(for: host) }
}

/// Generation 8: release a closed instance's store rather than let it linger
/// (and its cached documents with it) for the rest of the process.
extension QuestApp: AinkradAppTeardown {
    public static func teardown(instance: PluginInstanceID) {
        stores.remove(instance)
        // The MCP server's tool closures capture the operations layer, which
        // captures this instance's store. Leaving it registered would let the
        // assistant keep driving an app the user shut.
        mcpServers.remove(instance)
    }
}
