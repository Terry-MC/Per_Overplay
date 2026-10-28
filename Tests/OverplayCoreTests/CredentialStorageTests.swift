import XCTest
@testable import OverplayCore

final class CredentialStorageTests: XCTestCase {
    func testCredentialLivesInKeychainNotDatabase() throws {
        let service = "local.ds.overplay.tests.\(UUID().uuidString)"
        let keychain = KeychainCredentialStore(service: service)
        let store = try OverplayStore.inMemory()
        let account = try store.insertTestAccount(provider: .openrouter)
        let secret = "sk-test-credential-\(UUID().uuidString)"
        try keychain.setCredential(secret, accountId: account.id)
        defer { try? keychain.deleteAll() }

        XCTAssertEqual(try keychain.credential(accountId: account.id), secret)
        XCTAssertTrue(keychain.hasCredential(accountId: account.id))

        let csv = CSVExport.makeCSV(records: [], range: nil, isDemo: false)
        XCTAssertFalse(csv.contains(secret))
        let accountDescription = String(describing: try store.accounts())
        XCTAssertFalse(accountDescription.contains(secret))
    }

    func testDeleteCredential() throws {
        let service = "local.ds.overplay.tests.\(UUID().uuidString)"
        let keychain = KeychainCredentialStore(service: service)
        defer { try? keychain.deleteAll() }
        try keychain.setCredential("secret", accountId: "a")
        try keychain.deleteCredential(accountId: "a")
        XCTAssertNil(try keychain.credential(accountId: "a"))
    }

    func testInMemoryStore() throws {
        let store = InMemoryCredentialStore()
        try store.setCredential("secret", accountId: "a")
        XCTAssertEqual(try store.credential(accountId: "a"), "secret")
        try store.deleteAll()
        XCTAssertNil(try store.credential(accountId: "a"))
    }
}
