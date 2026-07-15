import Foundation

struct WindowDismissalContext: Equatable {
  var isPresented: Bool
  var isKeyWindow: Bool
  var hasAttachedSheet: Bool = false
  var hasVisibleOwnedChildWindow: Bool = false
  var hasVisibleCharacterPicker: Bool = false
  var hasVisibleUnrelatedAlert: Bool = false
}

enum WindowDismissalDecision: Equatable {
  case cancelDismissal
  case deferDismissal
  case dismiss
}

struct WindowDismissalPolicy {
  func decision(for context: WindowDismissalContext) -> WindowDismissalDecision {
    guard context.isPresented, !context.isKeyWindow else {
      return .cancelDismissal
    }

    if context.hasAttachedSheet || context.hasVisibleOwnedChildWindow
      || context.hasVisibleCharacterPicker
    {
      return .deferDismissal
    }

    // Unrelated application alerts must not keep the panel open.
    return .dismiss
  }
}

enum PanelLifecyclePhase: Equatable {
  case active
  case background

  static let notificationUserInfoKey = "phase"
}

extension Notification.Name {
  static let panelLifecyclePhaseDidChange = Notification.Name("panelLifecyclePhaseDidChange")
}

extension Notification {
  var panelLifecyclePhase: PanelLifecyclePhase? {
    userInfo?[PanelLifecyclePhase.notificationUserInfoKey] as? PanelLifecyclePhase
  }
}

@MainActor
final class PanelDismissalCoordinator {
  typealias Cancellation = @MainActor () -> Void
  typealias Scheduler =
    @MainActor (
      _ delay: TimeInterval,
      _ action: @escaping @MainActor () -> Void
    ) -> Cancellation

  private let policy: WindowDismissalPolicy
  private let delay: TimeInterval
  private let scheduler: Scheduler
  private let contextProvider: @MainActor () -> WindowDismissalContext
  private let dismiss: @MainActor () -> Void
  private let phaseDidChange: @MainActor (PanelLifecyclePhase) -> Void

  private var cancelPendingDismissal: Cancellation?
  private(set) var phase: PanelLifecyclePhase = .background

  init(
    policy: WindowDismissalPolicy = WindowDismissalPolicy(),
    delay: TimeInterval = 0.05,
    scheduler: Scheduler? = nil,
    contextProvider: @escaping @MainActor () -> WindowDismissalContext,
    dismiss: @escaping @MainActor () -> Void,
    phaseDidChange: @escaping @MainActor (PanelLifecyclePhase) -> Void
  ) {
    self.policy = policy
    self.delay = delay
    self.scheduler = scheduler ?? Self.defaultScheduler
    self.contextProvider = contextProvider
    self.dismiss = dismiss
    self.phaseDidChange = phaseDidChange
  }

  func panelDidBecomeKey() {
    cancelScheduledDismissal()
    setPhase(.active)
  }

  func panelDidResignKey() {
    scheduleDismissal()
  }

  func panelDidClose() {
    cancelScheduledDismissal()
    setPhase(.background)
  }

  private func scheduleDismissal() {
    cancelScheduledDismissal()
    cancelPendingDismissal = scheduler(delay) { [weak self] in
      guard let self else { return }
      self.cancelPendingDismissal = nil

      let context = self.contextProvider()
      switch self.policy.decision(for: context) {
      case .cancelDismissal:
        self.setPhase(context.isPresented && context.isKeyWindow ? .active : .background)
      case .deferDismissal:
        self.scheduleDismissal()
      case .dismiss:
        self.dismiss()
      }
    }
  }

  private func cancelScheduledDismissal() {
    cancelPendingDismissal?()
    cancelPendingDismissal = nil
  }

  private func setPhase(_ newPhase: PanelLifecyclePhase) {
    guard phase != newPhase else { return }
    phase = newPhase
    phaseDidChange(newPhase)
  }

  private static let defaultScheduler: Scheduler = { delay, action in
    let task = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      action()
    }
    return {
      task.cancel()
    }
  }
}
