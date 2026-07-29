import Testing
import Foundation
@testable import QuestFeature

@Suite("DocumentProjectRepository")
struct DocumentProjectRepositoryTests {
    @Test("a saved project reloads with its items")
    func roundTrip() {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let project = Project(id: UUID(), name: "Quest", kind: .software)
        let item = WorkItem(id: UUID(), projectID: project.id, parentID: nil,
                            type: .epic, title: "M1", statusID: "todo")

        repository.saveProject(ProjectDocument(project: project, items: [item]))

        let reloaded = repository.loadProject(project.id)
        #expect(reloaded?.project.name == "Quest")
        #expect(reloaded?.items.first?.title == "M1")
    }

    @Test("each project is its own document, keyed by id")
    func perProjectDocuments() {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let a = Project(id: UUID(), name: "A", kind: .software)
        let b = Project(id: UUID(), name: "B", kind: .general)

        repository.saveProject(ProjectDocument(project: a))
        repository.saveProject(ProjectDocument(project: b))

        #expect(documents.keys.contains("project-\(a.id.uuidString)"))
        #expect(documents.keys.contains("project-\(b.id.uuidString)"))
    }

    @Test("the index survives a round trip and is readable without project documents")
    func index() {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let project = Project(id: UUID(), name: "Ainkrad", kind: .software)

        repository.saveIndex([project.summary])

        #expect(repository.loadIndex().map(\.name) == ["Ainkrad"])
        #expect(repository.loadProject(project.id) == nil)
    }

    @Test("an empty store yields an empty index rather than failing")
    func emptyStore() {
        #expect(DocumentProjectRepository(documents: MemoryDocumentStore()).loadIndex().isEmpty)
    }

    @Test("removing a project deletes its document")
    func remove() {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let project = Project(id: UUID(), name: "Gone", kind: .general)
        repository.saveProject(ProjectDocument(project: project))

        repository.removeProject(project.id)

        #expect(repository.loadProject(project.id) == nil)
    }
}
