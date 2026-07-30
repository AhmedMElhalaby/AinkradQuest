import Testing
@testable import QuestFeature

@Suite("BreadcrumbTrail")
struct BreadcrumbTrailTests {
    @Test("Today with no project is just the app and the surface")
    func today() {
        #expect(BreadcrumbTrail.items(projectName: nil, surface: .today, sheet: nil)
                == ["Quest", "Today"])
    }

    @Test("a project surface names the project between app and surface")
    func projectSurface() {
        #expect(BreadcrumbTrail.items(projectName: "Ainkrad", surface: .board, sheet: nil)
                == ["Quest", "Ainkrad", "Board"])
    }

    @Test("a presented sheet appends as the deepest crumb")
    func sheet() {
        #expect(BreadcrumbTrail.items(projectName: "Ainkrad", surface: .list, sheet: "Settings")
                == ["Quest", "Ainkrad", "List", "Settings"])
    }

    @Test("a project name is ignored on Today, which is cross-project")
    func todayIgnoresProject() {
        #expect(BreadcrumbTrail.items(projectName: "Ainkrad", surface: .today, sheet: nil)
                == ["Quest", "Today"])
    }

    @Test("a blank or whitespace project name never yields an empty crumb")
    func blankName() {
        #expect(BreadcrumbTrail.items(projectName: "   ", surface: .board, sheet: nil)
                == ["Quest", "Board"])
    }
}
