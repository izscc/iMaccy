import Foundation

enum DebugPasteLog {
  static let url = URL(fileURLWithPath: "/tmp/imaccy-paste.log")

  static func write(_ message: String) {
    #if DEBUG
    let line = "[\(ISO8601DateFormatter().string(from: .now))] \(message)\n"
    let data = Data(line.utf8)

    if FileManager.default.fileExists(atPath: url.path) {
      if let handle = try? FileHandle(forWritingTo: url) {
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
      }
    } else {
      try? data.write(to: url)
    }
    #endif
  }

  static func reset() {
    #if DEBUG
    try? FileManager.default.removeItem(at: url)
    #endif
  }
}
