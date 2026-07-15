import Foundation

enum ItemAction: Equatable, Sendable {
  case copy
  case paste
  case pasteWithoutFormatting
}

enum ActivationSource: Equatable, Sendable {
  case keyboard
  case pointer
  case detailButton
}

@MainActor
final class ItemActionCoordinator {
  private let closePanel: () -> Void
  private let restoreFocus: () async -> Bool
  private let paste: () -> Void
  private var pendingPasteTask: Task<Void, Never>?

  init(
    closePanel: @escaping () -> Void,
    restoreFocus: @escaping () async -> Bool,
    paste: @escaping () -> Void
  ) {
    self.closePanel = closePanel
    self.restoreFocus = restoreFocus
    self.paste = paste
  }

  func perform(
    _ action: ItemAction,
    source: ActivationSource,
    copy: () -> Void,
    markUsed: () -> Void = {}
  ) {
    cancelPendingPaste()
    markUsed()
    copy()

    switch action {
    case .copy:
      if source != .detailButton {
        closePanel()
      }
    case .paste, .pasteWithoutFormatting:
      closePanel()
      pendingPasteTask = Task { @MainActor [weak self] in
        guard let self, await self.restoreFocus(), !Task.isCancelled else { return }
        self.paste()
        self.pendingPasteTask = nil
      }
    }
  }

  func cancelPendingPaste() {
    pendingPasteTask?.cancel()
    pendingPasteTask = nil
  }
}
