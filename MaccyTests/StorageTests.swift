import XCTest

@testable import iMaccy

@MainActor
final class StorageTests: XCTestCase {
  func testFileSizeUsesFileMetadata() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "imaccy-storage-size-\(UUID().uuidString)")
    let data = Data(repeating: 0xA5, count: 4_096)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertEqual(Storage.fileSize(at: url), Int64(data.count))
  }

  func testFileSizeReturnsNilForMissingFile() {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "imaccy-storage-missing-\(UUID().uuidString)")

    XCTAssertNil(Storage.fileSize(at: url))
  }
}
