import Defaults
import XCTest

@testable import iMaccy

@MainActor
final class PerformanceTests: XCTestCase {
  func testHistoryAddDeduplicatesAgainstLoadedItems() {
    let history = History.shared
    let savedSize = Defaults[.size]
    let savedSortBy = Defaults[.sortBy]
    defer {
      history.clearAll()
      Defaults[.size] = savedSize
      Defaults[.sortBy] = savedSortBy
    }

    history.clearAll()
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt

    let first = historyItem("same value")
    Storage.shared.context.insert(first)
    history.add(first)

    let second = historyItem("same value")
    Storage.shared.context.insert(second)
    history.add(second)

    XCTAssertEqual(history.all.count, 1)
    XCTAssertEqual(history.all.first?.text, "same value")
  }

  func testFindSimilarItemIn500LoadedEntriesPerformance() {
    measureFindSimilarItem(itemCount: 500)
  }

  func testFindSimilarItemIn5000LoadedEntriesPerformance() {
    measureFindSimilarItem(itemCount: 5_000)
  }

  func testHistoryAddWith500LoadedEntriesPerformance() {
    measureHistoryAdd(itemCount: 500)
  }

  func testHistoryAddWith5000LoadedEntriesPerformance() {
    measureHistoryAdd(itemCount: 5_000)
  }

  private func measureFindSimilarItem(itemCount: Int) {
    let items = (0..<itemCount).map { historyItem("value \($0)") }
    let duplicate = historyItem("value \(itemCount - 1)")

    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      XCTAssertNotNil(History.findSimilarItem(duplicate, in: items))
    }
  }

  private func measureHistoryAdd(itemCount: Int) {
    let history = History.shared
    let savedSize = Defaults[.size]
    defer {
      history.clearAll()
      Defaults[.size] = savedSize
    }

    let decorators = (0..<itemCount).map { index in
      HistoryItemDecorator(historyItem("loaded \(index)"))
    }
    history.all = decorators
    history.items = decorators
    Defaults[.size] = itemCount + 10

    let options = XCTMeasureOptions()
    options.iterationCount = 1
    measure(
      metrics: [XCTClockMetric(), XCTMemoryMetric()],
      options: options
    ) {
      let item = historyItem("new item")
      Storage.shared.context.insert(item)
      _ = history.add(item)
    }
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ])
    item.title = value
    return item
  }
}
