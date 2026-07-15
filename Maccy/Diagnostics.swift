import Foundation
import OSLog

enum Diagnostics {
  enum Name {
    static let coldLaunch: StaticString = "Cold Launch"
    static let firstPopup: StaticString = "First Popup"
    static let historyLoad: StaticString = "History Load"
    static let historySearch: StaticString = "History Search"
    static let historyAdd: StaticString = "History Add"
    static let promptLoad: StaticString = "Prompt Load"
    static let promptSearch: StaticString = "Prompt Search"
    static let promptBulkTags: StaticString = "Prompt Bulk Tags"
  }

  private static let signposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "in.zscc.iMaccy",
    category: "Performance"
  )

  static func begin(_ name: StaticString) -> OSSignpostIntervalState {
    signposter.beginInterval(name)
  }

  static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
    signposter.endInterval(name, state)
  }

  static func event(_ name: StaticString) {
    signposter.emitEvent(name)
  }

  static func measure<Result>(_ name: StaticString, operation: () throws -> Result) rethrows
    -> Result
  {
    let state = begin(name)
    defer { end(name, state) }
    return try operation()
  }
}
