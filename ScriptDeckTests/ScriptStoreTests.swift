import XCTest
@testable import ScriptDeck

final class ScriptStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptDeckStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testLoadMissingFileReturnsEmptyArray() async throws {
        let storeURL = tempDirectory.appendingPathComponent("ScriptDeck/scripts.json")
        let store = ScriptStore(fileURL: storeURL)

        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveAndLoadPersistsWithUserOnlyPermissions() async throws {
        let storeDir = tempDirectory.appendingPathComponent("ScriptDeck", isDirectory: true)
        let storeURL = storeDir.appendingPathComponent("scripts.json")
        let store = ScriptStore(fileURL: storeURL)

        let configs = [
            ScriptConfiguration(
                name: "Test Script",
                directory: "/tmp",
                command: "npm run dev"
            )
        ]

        try await store.save(configs)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, configs)

        let fileAttrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let filePerms = (fileAttrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(filePerms, 0o600)

        let dirAttrs = try FileManager.default.attributesOfItem(atPath: storeDir.path)
        let dirPerms = (dirAttrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(dirPerms, 0o700)
    }

    func testCorruptedJSONThrowsDecodeError() async throws {
        let storeURL = tempDirectory.appendingPathComponent("scripts.json")
        try Data("{not valid json".utf8).write(to: storeURL)
        let store = ScriptStore(fileURL: storeURL)

        do {
            _ = try await store.load()
            XCTFail("Expected decode error")
        } catch let error as ScriptStoreError {
            if case .decodeFailed = error {
                // expected
            } else {
                XCTFail("Unexpected ScriptStoreError: \(error)")
            }
        }
    }
}
