import XCTest

@testable import iMaccy

final class ThrottlerTests: XCTestCase {
  func testFirstInvocationIsScheduledImmediately() {
    let scheduler = TestScheduler()
    var invocationCount = 0
    let throttler = Throttler(
      minimumDelay: 1,
      clock: { 10 },
      scheduler: scheduler.schedule
    )

    throttler.throttle {
      invocationCount += 1
    }

    XCTAssertEqual(scheduler.scheduled.count, 1)
    XCTAssertEqual(scheduler.scheduled[0].delay, 0, accuracy: 0.000_001)

    scheduler.scheduled[0].workItem.perform()
    XCTAssertEqual(invocationCount, 1)
  }

  func testSubsequentInvocationWaitsOnlyForRemainingInterval() {
    let scheduler = TestScheduler()
    var now: TimeInterval = 10
    let throttler = Throttler(
      minimumDelay: 1,
      clock: { now },
      scheduler: scheduler.schedule
    )

    throttler.throttle {}
    scheduler.scheduled[0].workItem.perform()

    now = 10.25
    throttler.throttle {}

    XCTAssertEqual(scheduler.scheduled[1].delay, 0.75, accuracy: 0.000_001)
  }

  func testInvocationAfterMinimumIntervalIsScheduledImmediately() {
    let scheduler = TestScheduler()
    var now: TimeInterval = 10
    let throttler = Throttler(
      minimumDelay: 1,
      clock: { now },
      scheduler: scheduler.schedule
    )

    throttler.throttle {}
    scheduler.scheduled[0].workItem.perform()

    now = 11.5
    throttler.throttle {}

    XCTAssertEqual(scheduler.scheduled[1].delay, 0, accuracy: 0.000_001)
  }

  func testNewInvocationCancelsPendingWork() {
    let scheduler = TestScheduler()
    let throttler = Throttler(
      minimumDelay: 1,
      clock: { 10 },
      scheduler: scheduler.schedule
    )

    throttler.throttle {}
    let firstWorkItem = scheduler.scheduled[0].workItem
    throttler.throttle {}

    XCTAssertTrue(firstWorkItem.isCancelled)
    XCTAssertFalse(scheduler.scheduled[1].workItem.isCancelled)
  }
}

private final class TestScheduler {
  struct ScheduledWork {
    let delay: TimeInterval
    let workItem: DispatchWorkItem
  }

  private(set) var scheduled: [ScheduledWork] = []

  func schedule(after delay: TimeInterval, workItem: DispatchWorkItem) {
    scheduled.append(ScheduledWork(delay: delay, workItem: workItem))
  }
}
