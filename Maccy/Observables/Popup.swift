import AppKit.NSRunningApplication
import AppKit.NSWorkspace
import Defaults
import KeyboardShortcuts
import Observation

@MainActor
@Observable
class Popup {
  let verticalPadding: CGFloat = 5

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var pinnedItemsHeight: CGFloat = 0
  var footerHeight: CGFloat = 0
  private var previousApplicationPID: pid_t?

  init() {
    KeyboardShortcuts.onKeyUp(for: .popup) {
      self.toggle()
    }
  }

  func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if AppState.shared.appDelegate?.panel?.isPresented != true {
      rememberPreviousApplication()
    }
    AppState.shared.appDelegate?.panel.toggle(height: height, at: popupPosition)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    rememberPreviousApplication()
    AppState.shared.currentScope = Defaults[.defaultLibraryScope]
    self.height = AppState.shared.targetWindowSize(forTotalHeight: height).height
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()
  }

  func reactivatePreviousApplication() {
    guard let previousApplicationPID,
          let app = NSRunningApplication(processIdentifier: previousApplicationPID),
          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return
    }
    app.activate(options: [.activateIgnoringOtherApps])
  }

  func restoreFocusForPasting() async -> Bool {
    guard let previousApplicationPID,
          let target = NSRunningApplication(processIdentifier: previousApplicationPID),
          target.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return false
    }

    guard target.activate(options: [.activateIgnoringOtherApps]) else {
      return false
    }

    NSApp.hide(nil)

    for _ in 0..<15 where !target.isActive {
      try? await Task.sleep(for: .milliseconds(20))
      guard !Task.isCancelled else { return false }
    }

    // Give the target application one run-loop turn to restore its first responder.
    try? await Task.sleep(for: .milliseconds(20))
    return !Task.isCancelled && target.isActive
  }

  func resize(height: CGFloat) {
    let chromeHeight = headerHeight + pinnedItemsHeight + footerHeight + (verticalPadding * 2)
    let targetSize = AppState.shared.targetWindowSize(forTotalHeight: height + chromeHeight)
    self.height = targetSize.height
    AppState.shared.appDelegate?.panel.resize(to: targetSize)
    if AppState.shared.currentScope == .history {
      AppState.shared.recordHistoryPresentedWindowSize(targetSize)
    }
    needsResize = false
  }

  func rememberPreviousApplication() {
    guard let frontmost = NSWorkspace.shared.frontmostApplication,
          frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return
    }
    previousApplicationPID = frontmost.processIdentifier
  }
}
