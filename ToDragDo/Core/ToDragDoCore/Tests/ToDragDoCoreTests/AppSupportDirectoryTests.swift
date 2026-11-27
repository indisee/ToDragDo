import Foundation
import Testing
@testable import ToDragDoCore

@MainActor
@Suite("AppSupportDirectory")
struct AppSupportDirectoryTests {
    private var sharedAppSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    @Test("outside the sandbox, files never land in the shared Application Support")
    func unsandboxedGetsOwnFolder() throws {
        try #require(!AppSupportDirectory.isSandboxed, "tests run unsandboxed")
        let dir = try AppSupportDirectory.url()
        #expect(dir.standardizedFileURL != sharedAppSupport.standardizedFileURL)
        #expect(dir.deletingLastPathComponent().standardizedFileURL == sharedAppSupport.standardizedFileURL)
    }

    @Test("the default store lives in that folder")
    func defaultStoreIsScoped() throws {
        let store = try SwiftDataRescue.defaultStoreURL()
        #expect(store.deletingLastPathComponent().standardizedFileURL
                == (try AppSupportDirectory.url()).standardizedFileURL)
        #expect(store.deletingLastPathComponent().standardizedFileURL
                != sharedAppSupport.standardizedFileURL)
    }
}
