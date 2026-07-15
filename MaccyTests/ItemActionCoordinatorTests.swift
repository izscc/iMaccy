import XCTest

@testable import iMaccy

@MainActor
final class ItemActionCoordinatorTests: XCTestCase {
  func testDetailCopyDoesNotCloseOrPaste() {
    var events: [String] = []
    let coordinator = ItemActionCoordinator(
      closePanel: { events.append("close") },
      restoreFocus: {
        events.append("focus")
        return true
      },
      paste: { events.append("paste") }
    )

    coordinator.perform(.copy, source: .detailButton) {
      events.append("copy")
    }

    XCTAssertEqual(events, ["copy"])
  }

  func testKeyboardCopyClosesButNeverPastes() {
    var events: [String] = []
    let coordinator = ItemActionCoordinator(
      closePanel: { events.append("close") },
      restoreFocus: {
        events.append("focus")
        return true
      },
      paste: { events.append("paste") }
    )

    coordinator.perform(.copy, source: .keyboard) {
      events.append("copy")
    }

    XCTAssertEqual(events, ["copy", "close"])
  }

  func testPasteRestoresFocusBeforePostingPaste() async {
    var events: [String] = []
    let pasted = expectation(description: "paste posted")
    let coordinator = ItemActionCoordinator(
      closePanel: { events.append("close") },
      restoreFocus: {
        events.append("focus")
        return true
      },
      paste: {
        events.append("paste")
        pasted.fulfill()
      }
    )

    coordinator.perform(.paste, source: .pointer) {
      events.append("copy")
    }
    await fulfillment(of: [pasted], timeout: 1)

    XCTAssertEqual(events, ["copy", "close", "focus", "paste"])
  }

  func testPasteIsNotPostedWhenFocusRestorationFails() async {
    var events: [String] = []
    let coordinator = ItemActionCoordinator(
      closePanel: { events.append("close") },
      restoreFocus: {
        events.append("focus")
        return false
      },
      paste: { events.append("paste") }
    )

    coordinator.perform(.paste, source: .keyboard) {
      events.append("copy")
    }
    await Task.yield()

    XCTAssertEqual(events, ["copy", "close", "focus"])
  }

  func testNewActionCancelsPendingPaste() async {
    var events: [String] = []
    let restoreStarted = expectation(description: "restore started")
    let coordinator = ItemActionCoordinator(
      closePanel: { events.append("close") },
      restoreFocus: {
        restoreStarted.fulfill()
        try? await Task.sleep(for: .milliseconds(100))
        return !Task.isCancelled
      },
      paste: { events.append("paste") }
    )

    coordinator.perform(.paste, source: .keyboard) { events.append("first-copy") }
    await fulfillment(of: [restoreStarted], timeout: 1)
    coordinator.perform(.copy, source: .detailButton) { events.append("second-copy") }
    try? await Task.sleep(for: .milliseconds(150))

    XCTAssertFalse(events.contains("paste"))
  }
}
