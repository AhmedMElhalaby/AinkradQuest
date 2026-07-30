import SwiftUI
import AinkradAppKit

struct OverviewSurface: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let documents: PluginDocumentStore
    let theme: HostTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.project.name).font(.title2)
                if !document.project.summaryText.isEmpty {
                    Text(document.project.summaryText)
                }

                group("Links") {
                    LinkListView(store: store, target: .project(document.project.id),
                                links: document.project.links, theme: theme)
                    LinkEditor(store: store, target: .project(document.project.id), theme: theme)
                    // Always reachable, independent of any root grant and of
                    // whether a suggestion sheet ever fired for this project —
                    // see `FolderAttachButton`'s doc comment.
                    FolderAttachButton(store: store, projectID: document.project.id,
                                       documents: documents, theme: theme)
                }

                group("Epics") {
                    ForEach(document.items.filter { $0.type == .epic && !$0.isDeleted }) { epic in
                        let progress = EpicProgress.rollup(epicID: epic.id, in: document.items,
                                                           scheme: document.project.statusScheme)
                        HStack {
                            Text(epic.title)
                            Spacer()
                            ProgressView(value: progress.fraction).frame(width: 120)
                            Text("\(progress.done)/\(progress.total)").font(.caption)
                        }
                    }
                }

                group("Recent activity") {
                    ForEach(document.activity.suffix(20).reversed()) { event in
                        HStack {
                            Image(systemName: event.actor == .agent ? "sparkles" : "person")
                            Text(event.summary)
                            Spacer()
                            Text(event.at, style: .relative).font(.caption)
                        }
                    }
                }
            }
            .padding(16)
            .foregroundStyle(theme.tokens.foreground)
        }
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(theme.tokens.accentPrimary)
            content()
        }
    }
}
