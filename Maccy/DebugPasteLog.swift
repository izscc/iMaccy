import Foundation

enum DebugPasteLog {
  static let url = URL(fileURLWithPath: "/tmp/imaccy-paste.log")

  private static let allowedEvents: Set<String> = [
    "Accessibility.check",
    "AppState.selectPrompt",
    "AppState.selectPromptFromPointer",
    "Clipboard.paste",
    "History.select",
    "History.selectFromPointer",
    "HistoryItemView",
    "PromptRow",
    "applicationDidFinishLaunching"
  ]

  static func write(_ message: String) {
    #if DEBUG
    let candidate = message.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "unknown"
    let event = allowedEvents.contains(candidate) ? candidate : "redacted"
    let line = "[\(ISO8601DateFormatter().string(from: .now))] event=\(event)\n"
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
