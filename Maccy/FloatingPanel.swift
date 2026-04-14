import Defaults
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  var statusBarButton: NSStatusBarButton?

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
    let targetSize = AppState.shared.targetWindowSize(forTotalHeight: height)
    let targetOrigin = popupPosition.origin(size: targetSize, statusBarButton: statusBarButton)
    setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
    orderFrontRegardless()
    makeKey()
    isPresented = true

    if popupPosition == .statusItem {
      DispatchQueue.main.async {
        self.statusBarButton?.isHighlighted = true
      }
    }
  }

  func resize(to targetSize: NSSize, animate: Bool = true) {
    var newFrame = frame
    newFrame.origin.x -= (targetSize.width - frame.width) / 2
    newFrame.origin.y += (frame.height - targetSize.height)
    newFrame.size = targetSize

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

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      guard self.isPresented else { return }
      guard !self.shouldRemainPresentedAfterResign else { return }
      self.close()
    }
  }

  override func close() {
    if AppState.shared.currentScope == .history {
      AppState.shared.recordHistoryPresentedWindowSize(frame.size)
    }
    super.close()
    isPresented = false
    statusBarButton?.isHighlighted = false
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }

  var shouldRemainPresentedAfterResign: Bool {
    if NSApp.isActive {
      return true
    }

    if attachedSheet != nil || NSApp.modalWindow != nil || NSApp.alertWindow != nil {
      return true
    }

    if (childWindows ?? []).contains(where: \.isVisible) {
      return true
    }

    return NSApp.windows.contains(where: { window in
      window != self &&
      window.isVisible &&
      (window.sheetParent == self || window.parent == self)
    })
  }
}
