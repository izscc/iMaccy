import XCTest

@testable import iMaccy

final class WindowDismissalPolicyTests: XCTestCase {
  private let policy = WindowDismissalPolicy()

  func testDismissesForUnrelatedAlert() {
    let context = WindowDismissalContext(
      isPresented: true,
      isKeyWindow: false,
      hasVisibleUnrelatedAlert: true
    )

    XCTAssertEqual(policy.decision(for: context), .dismiss)
  }

  func testDefersForOwnedSheet() {
    let context = WindowDismissalContext(
      isPresented: true,
      isKeyWindow: false,
      hasAttachedSheet: true
    )

    XCTAssertEqual(policy.decision(for: context), .deferDismissal)
  }

  func testDefersForOwnedChildWindow() {
    let context = WindowDismissalContext(
      isPresented: true,
      isKeyWindow: false,
      hasVisibleOwnedChildWindow: true
    )

    XCTAssertEqual(policy.decision(for: context), .deferDismissal)
  }

  func testDefersForCharacterPicker() {
    let context = WindowDismissalContext(
      isPresented: true,
      isKeyWindow: false,
      hasVisibleCharacterPicker: true
    )

    XCTAssertEqual(policy.decision(for: context), .deferDismissal)
  }
}

@MainActor
final class PanelDismissalCoordinatorTests: XCTestCase {
  func testRegainingKeyCancelsPendingDismissalAndTimeoutRechecksState() {
    let scheduler = ManualDismissalScheduler()
    var context = WindowDismissalContext(isPresented: true, isKeyWindow: false)
    var dismissCount = 0
    var phases: [PanelLifecyclePhase] = []
    let coordinator = PanelDismissalCoordinator(
      scheduler: scheduler.schedule,
      contextProvider: { context },
      dismiss: { dismissCount += 1 },
      phaseDidChange: { phases.append($0) }
    )

    coordinator.panelDidResignKey()
    context.isKeyWindow = true
    coordinator.panelDidBecomeKey()

    XCTAssertTrue(scheduler.actions.first?.isCancelled == true)
    scheduler.runAll(includingCancelled: true)
    XCTAssertEqual(dismissCount, 0)
    XCTAssertEqual(coordinator.phase, .active)
    XCTAssertEqual(phases, [.active])
  }

  func testDismissesAfterDelayWhenPanelRemainsResigned() {
    let scheduler = ManualDismissalScheduler()
    let context = WindowDismissalContext(isPresented: true, isKeyWindow: false)
    var dismissCount = 0
    let coordinator = PanelDismissalCoordinator(
      scheduler: scheduler.schedule,
      contextProvider: { context },
      dismiss: { dismissCount += 1 },
      phaseDidChange: { _ in }
    )

    coordinator.panelDidResignKey()
    scheduler.runAll()

    XCTAssertEqual(dismissCount, 1)
  }

  func testOwnedWindowDefersUntilBlockerDisappears() {
    let scheduler = ManualDismissalScheduler()
    var context = WindowDismissalContext(
      isPresented: true,
      isKeyWindow: false,
      hasAttachedSheet: true
    )
    var dismissCount = 0
    let coordinator = PanelDismissalCoordinator(
      scheduler: scheduler.schedule,
      contextProvider: { context },
      dismiss: { dismissCount += 1 },
      phaseDidChange: { _ in }
    )

    coordinator.panelDidResignKey()
    scheduler.runAll()
    XCTAssertEqual(dismissCount, 0)
    XCTAssertEqual(scheduler.actions.count, 1)

    context.hasAttachedSheet = false
    scheduler.runAll()
    XCTAssertEqual(dismissCount, 1)
  }
}

@MainActor
private final class ManualDismissalScheduler {
  final class ScheduledAction {
    let action: @MainActor () -> Void
    var isCancelled = false

    init(action: @escaping @MainActor () -> Void) {
      self.action = action
    }
  }

  var actions: [ScheduledAction] = []

  func schedule(
    delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> PanelDismissalCoordinator.Cancellation {
    let scheduledAction = ScheduledAction(action: action)
    actions.append(scheduledAction)
    return {
      scheduledAction.isCancelled = true
    }
  }

  func runAll(includingCancelled: Bool = false) {
    let currentActions = actions
    actions.removeAll()
    for scheduledAction in currentActions where includingCancelled || !scheduledAction.isCancelled {
      scheduledAction.action()
    }
  }
}
