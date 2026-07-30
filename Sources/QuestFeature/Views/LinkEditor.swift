import SwiftUI
import AinkradAppKit

/// Input validation at the boundary where links enter the system.
public enum LinkValidation {
    public enum Outcome {
        case valid(Link)
        case invalid(String)

        public var value: Link? { if case .valid(let link) = self { link } else { nil } }
        public var isFailure: Bool { value == nil }
    }

    /// Repo-scoped schemes must name their repo: a project with eleven repos
    /// cannot resolve a bare branch name, and storing one would produce a link
    /// that looks fine and goes nowhere.
    public static func normalize(scheme: LinkScheme, identifier: String,
                                 label: String, repo: String?) -> Outcome {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return .invalid("A link needs an identifier.") }

        let repoScoped: Set<LinkScheme> = [.branch, .pr, .commit]
        let trimmedRepo = repo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if repoScoped.contains(scheme), trimmedRepo?.isEmpty != false {
            return .invalid("A \(scheme.rawValue) link must say which repo it belongs to.")
        }

        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return .valid(Link(scheme: scheme, identifier: trimmedIdentifier,
                           label: trimmedLabel.isEmpty ? trimmedIdentifier : trimmedLabel,
                           repo: repoScoped.contains(scheme) ? trimmedRepo : nil))
    }
}

struct LinkEditor: View {
    @Bindable var store: ProjectStore
    /// What this editor attaches to — a project or one work item.
    let target: LinkTarget
    let theme: HostTheme

    @State private var scheme: LinkScheme = .repo
    @State private var identifier = ""
    @State private var label = ""
    @State private var repo = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: $scheme) {
                ForEach([LinkScheme.repo, .folder, .file, .url, .branch, .pr, .commit],
                        id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Identifier (path, URL, branch name…)", text: $identifier)
            TextField("Label", text: $label)
            if [.branch, .pr, .commit].contains(scheme) {
                TextField("Repo", text: $repo)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
            Button("Add link", action: add)
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
    }

    private func add() {
        switch LinkValidation.normalize(scheme: scheme, identifier: identifier,
                                        label: label, repo: repo) {
        case .invalid(let message):
            error = message
        case .valid(let link):
            do {
                try store.addLink(to: target, link: link, actor: .user)
                identifier = ""; label = ""; repo = ""; error = nil
            } catch let failure as QuestError {
                error = failure.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Renders a target's links with a remove control. Used by Overview (project
/// links) and ItemEditor (item links) so the two cannot drift.
struct LinkListView: View {
    @Bindable var store: ProjectStore
    let target: LinkTarget
    let links: [Link]
    let theme: HostTheme

    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(links) { link in
                HStack {
                    Image(systemName: LinkSymbol.name(for: link.scheme))
                    Text(link.label)
                    if let repo = link.repo {
                        Text(repo).font(.caption)
                            .foregroundStyle(theme.tokens.foreground.opacity(0.6))
                    }
                    Spacer()
                    Button {
                        remove(link)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
        }
        .foregroundStyle(theme.tokens.foreground)
    }

    private func remove(_ link: Link) {
        do {
            // No bookmark to clean up: attachments store a path, not a
            // security-scoped bookmark (see `FolderAttachment`). That is what
            // makes every removal path — here, `remove_link` over MCP, project
            // delete — leak-free by construction rather than by remembering.
            try store.removeLink(from: target, link: link, actor: .user)
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The SF Symbol for a link kind, shared so Overview and ItemEditor agree.
enum LinkSymbol {
    static func name(for scheme: LinkScheme) -> String {
        switch scheme {
        case .repo: "shippingbox"
        case .branch: "arrow.triangle.branch"
        case .pr: "arrow.triangle.pull"
        case .commit: "circle.dotted"
        case .folder: "folder"
        case .file: "doc"
        case .url: "link"
        case .unknown: "questionmark"
        }
    }
}
