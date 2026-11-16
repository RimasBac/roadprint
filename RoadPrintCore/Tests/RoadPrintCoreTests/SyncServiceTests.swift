import Testing
@testable import RoadPrintCore

@Test func onlyAccountAndQuotaProblemsShowABanner() {
    #expect(SyncStatus.noAccount.banner == .iCloudUnavailable)
    #expect(SyncStatus.quotaFull.banner == .storageFull)
    for status in [SyncStatus.available, .off, .error] {
        #expect(status.banner == nil)
    }
}

@Test func localOnlySyncStaysOff() async throws {
    let sync = LocalOnlySyncService()
    try await sync.setEnabled(true)
    #expect(await sync.status() == .off)
}
