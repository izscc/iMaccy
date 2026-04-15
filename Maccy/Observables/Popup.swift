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

  func restoreFocusForPasting() {
    if let previousApplicationPID,
       let app = NSRunningApplication(processIdentifier: previousApplicationPID),
       app.bundleIdentifier != Bundle.main.bundleIdentifier {
      app.activate(options: [.activateIgnoringOtherApps])
    }

    DispatchQueue.main.async {
      NSApp.hide(nil)
    }
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
