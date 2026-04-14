import AppKit.NSRunningApplication
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

  init() {
    KeyboardShortcuts.onKeyUp(for: .popup) {
      self.toggle()
    }
  }

  func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.toggle(height: height, at: popupPosition)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.currentScope = Defaults[.defaultLibraryScope]
    self.height = AppState.shared.targetWindowSize(forTotalHeight: height).height
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()
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
}
