import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  private static let oldDirectoryName = "Maccy"
  private static let newDirectoryName = "iMaccy"
  private static let databaseFileName = "Storage.sqlite"

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? Data(contentsOf: url), size.count > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: Int64(size.count))
  }

  private let url = Storage.prepareStorageURL()

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(
        for: HistoryItem.self,
        HistoryItemContent.self,
        PromptItem.self,
        PromptCategory.self,
        PromptTag.self,
        PromptItemTagLink.self,
        configurations: config
      )
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  private static func prepareStorageURL() -> URL {
    let fileManager = FileManager.default
    let baseDirectory = URL.applicationSupportDirectory
    let newDirectory = baseDirectory.appending(path: newDirectoryName)
    let newURL = newDirectory.appending(path: databaseFileName)

    try? fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      return newURL
    }
    #endif

    let oldDirectory = baseDirectory.appending(path: oldDirectoryName)
    let oldURL = oldDirectory.appending(path: databaseFileName)

    if !fileManager.fileExists(atPath: newURL.path),
       fileManager.fileExists(atPath: oldURL.path) {
      copyIfNeeded(from: oldURL, to: newURL)
      copyIfNeeded(from: oldURL.appendingPathExtension("wal"), to: newURL.appendingPathExtension("wal"))
      copyIfNeeded(from: oldURL.appendingPathExtension("shm"), to: newURL.appendingPathExtension("shm"))
    }

    return newURL
  }

  private static func copyIfNeeded(from source: URL, to destination: URL) {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path) else { return }
    guard !fileManager.fileExists(atPath: destination.path) else { return }
    try? fileManager.copyItem(at: source, to: destination)
  }
}
