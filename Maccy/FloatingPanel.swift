import Defaults
import OSLog
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  var statusBarButton: NSStatusBarButton?
  private var hasRecordedFirstOpen = false
  private var firstPopupInterval: OSSignpostIntervalState?

  private lazy var dismissalCoordinator = PanelDismissalCoordinator(
    contextProvider: { [weak self] in
      self?.windowDismissalContext ?? WindowDismissalContext(isPresented: false, isKeyWindow: false)
    },
    dismiss: { [weak self] in
      self?.close()
    },
    phaseDidChange: { phase in
      NotificationCenter.default.post(
        name: .panelLifecyclePhaseDidChange,
        object: nil,
        userInfo: [PanelLifecyclePhase.notificationUserInfoKey: phase]
      )
    }
  )

  override var isMovable: Bool {
    get { Defaults[.popupPosition] != .statusItem }
    set {}
  }

  init(
    contentRect: NSRect,
    identifier: String = "",
    statusBarButton: NSStatusBarButton? = nil,
    view: () -> Content
  ) {
    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    self.statusBarButton = statusBarButton
    self.identifier = NSUserInterfaceItemIdentifier(identifier)

    Defaults[.windowSize] = contentRect.size
    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = NSHostingView(
      rootView: view()
        // The safe area is ignored because the title bar still interferes with the geometry
        .ignoresSafeArea()
        .gesture(DragGesture()
          .onEnded { _ in
            self.saveWindowFrame(frame: self.frame)
        })
    )
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if !hasRecordedFirstOpen {
      firstPopupInterval = Diagnostics.begin(Diagnostics.Name.firstPopup)
      hasRecordedFirstOpen = true
    }
    let targetSize = AppState.shared.targetWindowSize(forTotalHeight: height)
    applyMinimumSize(for: AppState.shared.currentScope)
    let targetOrigin = popupPosition.origin(size: targetSize, statusBarButton: statusBarButton)
    setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
    isPresented = true
    orderFrontRegardless()
    makeKey()

    if popupPosition == .statusItem {
      DispatchQueue.main.async {
        self.statusBarButton?.isHighlighted = true
      }
    }
  }

  func resize(to targetSize: NSSize, animate: Bool = true) {
    applyMinimumSize(for: AppState.shared.currentScope)
    var newFrame = frame
    newFrame.origin.x -= (targetSize.width - frame.width) / 2
    newFrame.origin.y += (frame.height - targetSize.height)
    newFrame.size = targetSize
    newFrame = clampedFrame(newFrame)

    if animate {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        animator().setFrame(newFrame, display: true)
      }
    } else {
      setFrame(newFrame, display: true)
    }

    if AppState.shared.currentScope == .history {
      AppState.shared.recordHistoryPresentedWindowSize(newFrame.size)
    }
  }

  func verticallyResize(to newHeight: CGFloat) {
    resize(to: NSSize(width: frame.width, height: newHeight))
  }

  func saveWindowFrame(frame: NSRect) {
    if AppState.shared.currentScope == .history {
      Defaults[.windowSize] = frame.size
      AppState.shared.recordHistoryPresentedWindowSize(frame.size)
    }

    if let screenFrame = screen?.visibleFrame {
      let anchorX = frame.minX + frame.width / 2 - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    saveWindowFrame(frame: NSRect(origin: frame.origin, size: frameSize))

    return frameSize
  }

  func windowDidBecomeKey(_ notification: Notification) {
    AppState.shared.itemActionCoordinator.cancelPendingPaste()
    if let firstPopupInterval {
      Diagnostics.end(Diagnostics.Name.firstPopup, firstPopupInterval)
      self.firstPopupInterval = nil
    }
    dismissalCoordinator.panelDidBecomeKey()
  }

  // Close automatically when out of focus, e.g. outside click.
  func windowDidResignKey(_ notification: Notification) {
    dismissalCoordinator.panelDidResignKey()
  }

  override func close() {
    if let firstPopupInterval {
      Diagnostics.end(Diagnostics.Name.firstPopup, firstPopupInterval)
      self.firstPopupInterval = nil
    }
    if AppState.shared.currentScope == .history {
      AppState.shared.recordHistoryPresentedWindowSize(frame.size)
    }
    super.close()
    isPresented = false
    statusBarButton?.isHighlighted = false
    dismissalCoordinator.panelDidClose()
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }

  private func applyMinimumSize(for scope: LibraryScope) {
    switch scope {
    case .history:
      minSize = NSSize(width: 320, height: 240)
    case .prompt, .favorites:
      minSize = NSSize(
        width: AppState.shared.promptExpandedMinWidth,
        height: AppState.shared.promptMinimumHeight
      )
    }
  }

  private func clampedFrame(_ proposedFrame: NSRect) -> NSRect {
    guard let visibleFrame = screen?.visibleFrame ?? NSScreen.forPopup?.visibleFrame else {
      return proposedFrame
    }

    var frame = proposedFrame
    if frame.width > visibleFrame.width {
      frame.size.width = visibleFrame.width
    }
    if frame.height > visibleFrame.height {
      frame.size.height = visibleFrame.height
    }

    frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
    frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
    return frame
  }

  private var windowDismissalContext: WindowDismissalContext {
    let visibleOwnedWindows = NSApp.windows.filter { window in
      window !== self && window.isVisible && owns(window)
    }
    let hasVisibleUnrelatedAlert = NSApp.alertWindow.map { alert in
      alert.isVisible && !owns(alert)
    } ?? false

    return WindowDismissalContext(
      isPresented: isPresented,
      isKeyWindow: isKeyWindow,
      hasAttachedSheet: attachedSheet != nil || visibleOwnedWindows.contains(where: { $0.sheetParent === self }),
      hasVisibleOwnedChildWindow: visibleOwnedWindows.contains(where: { $0.sheetParent == nil }) ||
        (childWindows ?? []).contains(where: \.isVisible),
      hasVisibleCharacterPicker: NSApp.characterPickerWindow?.isVisible == true,
      hasVisibleUnrelatedAlert: hasVisibleUnrelatedAlert
    )
  }

  private func owns(_ window: NSWindow) -> Bool {
    window.sheetParent === self ||
      window.parent === self ||
      (childWindows ?? []).contains(where: { $0 === window })
  }
}
