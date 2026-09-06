import Foundation
import Testing
@testable import QuestFeature

@Suite("SnapshotStore tolerance")
struct SnapshotStoreToleranceTests {
    @Test @MainActor func pollToleranceIsHalfTheInterval() {
        #expect(SnapshotStore.pollTolerance == SnapshotStore.pollInterval * 0.5)
    }

    @Test @MainActor func pollToleranceIsGenerousEnoughToCoalesce() {
        // A tolerance below ~1s buys nothing: the coalescing window the kernel
        // uses is measured in seconds, not milliseconds.
        #expect(SnapshotStore.pollTolerance >= 1.0)
    }
}
