import Foundation

extension ProjectStore {
    /// Applies an already-validated `SchemePlan.Plan` to one project.
    ///
    /// Atomic by construction: every change is made to a local copy of the
    /// document and committed once, so a scheme edit cannot land half-applied.
    /// Validation is NOT repeated here — `SchemePlan.plan` owns it, and the
    /// plan's own contents are what execute, which is what keeps the confirm
    /// step honest.
    public func applyScheme(_ plan: SchemePlan.Plan, to projectID: UUID,
                            actor: ActivityActor) throws {
        guard !isTrashed(projectID), var document = openProject(projectID) else {
            throw QuestError.projectNotFound(projectID)
        }

        document.project.statusScheme = plan.proposed

        // Reassign items off removed statuses. Soft-deleted items included: they
        // keep a statusID, and a restore must not bring back an item pointing at
        // a status that no longer exists.
        if !plan.reassignments.isEmpty {
            for position in document.items.indices {
                if let destination = plan.reassignments[document.items[position].statusID] {
                    document.items[position].statusID = destination
                    document.items[position].updatedAt = Date()
                }
            }
        }

        // A category change decides retroactively whether items in that status
        // count as finished.
        let closing = Set(plan.closing), reopening = Set(plan.reopening)
        let stamp = Date()
        for position in document.items.indices {
            let id = document.items[position].id
            if closing.contains(id) {
                document.items[position].closedAt = stamp
                document.items[position].updatedAt = stamp
            } else if reopening.contains(id) {
                document.items[position].closedAt = nil
                document.items[position].updatedAt = stamp
            }
        }

        document.project.updatedAt = stamp
        document.activity.append(ActivityEvent(projectID: projectID, actor: actor,
                                               kind: .schemeUpdated,
                                               summary: plan.summary))
        commit(document)
    }
}
