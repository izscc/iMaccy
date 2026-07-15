import Foundation

// Based on https://www.craftappco.com/blog/2018/5/30/simple-throttling-in-swift.
class Throttler {
  typealias Clock = () -> TimeInterval
  typealias Scheduler = (_ delay: TimeInterval, _ workItem: DispatchWorkItem) -> Void

  var minimumDelay: TimeInterval

  private var workItem: DispatchWorkItem = DispatchWorkItem(block: {})
  private var previousRun: TimeInterval?
  private let clock: Clock
  private let scheduler: Scheduler

  init(minimumDelay: TimeInterval, queue: DispatchQueue = DispatchQueue.main) {
    self.minimumDelay = minimumDelay
    self.clock = { ProcessInfo.processInfo.systemUptime }
    self.scheduler = { delay, workItem in
      queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
  }

  init(minimumDelay: TimeInterval, clock: @escaping Clock, scheduler: @escaping Scheduler) {
    self.minimumDelay = minimumDelay
    self.clock = clock
    self.scheduler = scheduler
  }

  func throttle(_ block: @escaping () -> Void) {
    // Cancel any existing work item if it has not yet executed
    cancel()

    // Re-assign workItem with the new block task,
    // resetting the previousRun time when it executes.
    workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.previousRun = self.clock()
      block()
    }

    let delay: TimeInterval
    if let previousRun {
      let elapsed = max(0, clock() - previousRun)
      delay = max(0, minimumDelay - elapsed)
    } else {
      delay = 0
    }
    scheduler(delay, workItem)
  }

  func cancel() {
    workItem.cancel()
  }
}
