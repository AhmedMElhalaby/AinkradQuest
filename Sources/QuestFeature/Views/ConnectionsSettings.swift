import SwiftUI
import Foundation
import AinkradAppKit

/// The add/edit form's state, split out of the view so validation is testable
/// without a view host — the same split `ProjectSettingsValidationTests` uses.
public struct ConnectionDraft: Equatable {
    public var provider: ProviderKind
    public var accountLabel: String = ""
    public var accountIdentifier: String = ""
    public var baseURLText: String = ""
    public var secret: String = ""

    public init(provider: ProviderKind) {
        self.provider = provider
    }

    /// Whether this provider is addressed by site. Jira is per-site and GitHub
    /// may be Enterprise; Linear is a single host.
    public var requiresBaseURL: Bool {
        provider == .jira
    }

    public var baseURL: URL? {
        let trimmed = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil, url.host != nil
        else { return nil }
        return url
    }

    public var validationMessage: String? {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if blank(accountLabel) { return "Give this account a name." }
        if blank(accountIdentifier) { return "Enter the account's email or login." }
        if requiresBaseURL && blank(baseURLText) {
            return "Jira needs the site URL, e.g. https://you.atlassian.net"
        }
        if !blank(baseURLText) && baseURL == nil { return "That site URL is not valid." }
        if blank(secret) { return "A token is required." }
        return nil
    }

    public var isValid: Bool { validationMessage == nil }
}

/// Manage the accounts Quest can reach. One row per connection, showing which
/// provider it speaks to and how many projects are bound to it.
///
/// Presented inside `QuestSettingsView`'s stack, so it renders a
/// `AinkradSectionFrame` rather than owning a window.
struct ConnectionsSettings: View {
    @Bindable var registry: ConnectionRegistry
    let store: ProjectStore
    /// Same contract as `ProjectSettingsSheet`: this view never presents its
    /// own error UI, it reports upward.
    let report: (String, AinkradStatus) -> Void

    @State private var draft: ConnectionDraft?
    /// Bumped every time the editor is (re)opened, and used as the modal's
    /// `.id(...)`. `.ainkradModal` REUSES its content view across a change of
    /// the presented item — without a key, reopening after Cancel would hand
    /// the fresh `ConnectionDraft` init argument to a view that kept the
    /// previous open's stale `@State` draft.
    @State private var draftToken = UUID()

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradSectionFrame(title: "Connections") {
            VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                if let failure = registry.persistenceFailure {
                    Text(failure).foregroundStyle(theme.foreground.opacity(0.7))
                }
                ForEach(registry.connections) { connection in
                    row(connection)
                }
                AinkradButton(title: "Add Connection…", style: .secondary) {
                    draftToken = UUID()
                    draft = ConnectionDraft(provider: .linear)
                }
            }
        }
        // `.ainkradModal` is an overlay modifier with no intrinsic
        // `DismissAction` — closing is this view's own job via `onClose`,
        // exactly as `ProjectSettingsSheet`/`ItemEditor` do.
        .ainkradModal(isPresented: Binding(get: { draft != nil },
                                           set: { if !$0 { draft = nil } })) {
            if let current = draft {
                ConnectionEditor(draft: current, registry: registry, report: report,
                                 onClose: { draft = nil })
                    .id(draftToken)
            }
        }
    }

    private func row(_ connection: Connection) -> some View {
        let bound = store.projectCount(boundTo: connection.id)
        return AinkradFormRow(title: connection.accountLabel,
                              help: "\(connection.provider.rawValue) · \(connection.accountIdentifier) · \(bound) project\(bound == 1 ? "" : "s")") {
            AinkradButton(title: "Remove", style: .secondary) {
                remove(connection, bound: bound)
            }
        }
    }

    private func remove(_ connection: Connection, bound: Int) {
        do {
            try registry.removeConnection(connection.id, boundProjectCount: bound)
            // The guard above only counts LIVE projects, deliberately: a
            // connection you can never delete because something sits forgotten
            // in the trash is a worse failure than a stale field. So the
            // trashed ones are severed here instead — otherwise restoring a
            // project from trash would resurrect a `connectionID` pointing at
            // a connection that no longer exists.
            store.severBindings(toConnection: connection.id, actor: .user)
        } catch let failure as QuestError {
            // The in-use refusal is the COMMON case and must be shown, not
            // swallowed — otherwise the button looks broken.
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }
}

/// Add-connection form. A form with a provider picker restricted to the three
/// real providers (never `.local`, which is not something anyone adds), text
/// fields bound to the draft, a masked secret field, and inline validation.
///
/// Presented through `.ainkradModal`, which injects no `DismissAction` — this
/// view must never reach for `@Environment(\.dismiss)`. Closing happens via
/// `onClose`, called as the LAST statement of a path.
struct ConnectionEditor: View {
    @State private var draft: ConnectionDraft
    let registry: ConnectionRegistry
    let report: (String, AinkradStatus) -> Void
    let onClose: () -> Void

    @Environment(\.ainkradTheme) private var theme

    /// Providers a user can actually add a connection for. `.local` is the
    /// native tracker, never something anyone connects to.
    private static let addableProviders: [ProviderKind] = [.jira, .linear, .githubProjects]

    init(draft: ConnectionDraft, registry: ConnectionRegistry,
         report: @escaping (String, AinkradStatus) -> Void,
         onClose: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.registry = registry
        self.report = report
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Add connection", subtitle: nil)

            AinkradFormRow(title: "Provider") {
                AinkradSegmentedPicker(items: Self.addableProviders, selection: $draft.provider) {
                    $0.settingsTitle
                }
            }
            AinkradFormRow(title: "Name") {
                AinkradTextField(text: $draft.accountLabel, placeholder: "e.g. Work")
            }
            AinkradFormRow(title: "Account", help: "Email or login the provider knows you by.") {
                AinkradTextField(text: $draft.accountIdentifier, placeholder: "you@example.com")
            }
            if draft.requiresBaseURL {
                AinkradFormRow(title: "Site URL") {
                    AinkradTextField(text: $draft.baseURLText, placeholder: "https://you.atlassian.net")
                }
            }
            AinkradFormRow(title: "Token") {
                AinkradSecureField(text: $draft.secret, placeholder: "Token")
            }

            if let message = draft.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.foreground.opacity(0.7))
            }

            HStack {
                AinkradButton(title: "Cancel", style: .secondary, action: onClose)
                Spacer()
                AinkradButton(title: "Add", style: .primary, action: submit)
                    .disabled(!draft.isValid)
            }
        }
        .frame(width: 420)
        .foregroundStyle(theme.foreground)
        .onSubmit(submit)
        // `AinkradButton` carries no keyboard shortcut, so the `.defaultAction`
        // the old `Button("Add")` would have had is otherwise lost — with no
        // text field focused there would be nothing for Return to do.
        .background(defaultActionSubmit)
    }

    /// Return-with-nothing-focused submits, exactly as `ItemEditor`'s
    /// `defaultActionSave` does.
    private var defaultActionSubmit: some View {
        Button("") { submit() }
            .keyboardShortcut(.defaultAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func submit() {
        guard draft.isValid else { return }
        do {
            try registry.addConnection(provider: draft.provider,
                                       accountLabel: draft.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                                       accountIdentifier: draft.accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                                       baseURL: draft.baseURL,
                                       secret: draft.secret)
            // LAST statement on this path — everything after it would run in an
            // unmounted subtree.
            onClose()
        } catch let failure as QuestError {
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }
}

private extension ProviderKind {
    /// The label the settings picker shows. Local to this file because it is a
    /// UI string, not part of the persisted vocabulary.
    var settingsTitle: String {
        switch self {
        case .local: "Local"
        case .jira: "Jira"
        case .linear: "Linear"
        case .githubProjects: "GitHub Projects"
        }
    }
}
