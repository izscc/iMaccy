import XCTest

@testable import iMaccy

final class PromptSnapshotTests: XCTestCase {
  func testBuildsIndexesAndCounts() {
    let root = PromptCategory(name: "Prompt", isSystem: true)
    let work = PromptCategory(name: "Work", parentID: root.id)
    let swift = PromptTag(name: "Swift")
    let review = PromptTag(name: "代码 审查")
    let first = PromptItem(
      title: "First", plainText: "Review Swift", normalizedText: "review swift", categoryID: root.id
    )
    let second = PromptItem(
      title: "Second", plainText: "Write docs", normalizedText: "write docs", categoryID: work.id)
    let links = [
      PromptItemTagLink(promptItemID: first.id, promptTagID: swift.id),
      PromptItemTagLink(promptItemID: first.id, promptTagID: review.id),
      PromptItemTagLink(promptItemID: second.id, promptTagID: swift.id),
    ]

    let snapshot = PromptSnapshot(
      items: [first, second],
      categories: [root, work],
      tags: [swift, review],
      links: links
    )

    XCTAssertEqual(snapshot.categoryByID[work.id]?.name, "Work")
    XCTAssertEqual(snapshot.tagIDsByPromptID[first.id], Set([swift.id, review.id]))
    XCTAssertEqual(snapshot.tagsByPromptID[first.id]?.count, 2)
    XCTAssertEqual(snapshot.categoryCounts[root.id], 1)
    XCTAssertEqual(snapshot.tagCounts[swift.id], 2)
  }

  func testFiltersRootCategoryAndUnknownTags() {
    let root = PromptCategory(name: "Prompt", isSystem: true)
    let tag = PromptTag(name: "代码 审查")
    let rootPrompt = PromptItem(
      title: "Root", plainText: "Need review", normalizedText: "need review", categoryID: root.id)
    let unassigned = PromptItem(
      title: "Unassigned", plainText: "Other", normalizedText: "other", categoryID: nil)
    let work = PromptCategory(name: "Work", parentID: root.id)
    let nested = PromptItem(
      title: "Work", plainText: "Work item", normalizedText: "work item", categoryID: work.id)

    let snapshot = PromptSnapshot(
      items: [rootPrompt, unassigned, nested],
      categories: [root, work],
      tags: [tag],
      links: [PromptItemTagLink(promptItemID: rootPrompt.id, promptTagID: tag.id)]
    )

    let rootResult = snapshot.result(categoryFilter: .root)
    XCTAssertEqual(Set(rootResult.items.map(\.id)), Set([rootPrompt.id, unassigned.id]))

    let unknownResult = snapshot.result(searchQuery: "#missing")
    XCTAssertTrue(unknownResult.items.isEmpty)
    XCTAssertEqual(unknownResult.unknownTagNames, ["missing"])
  }

  func testSortsByUsageFrequencyThenUpdatedAt() {
    let now = Date()
    let low = PromptItem(
      title: "Low",
      plainText: "low",
      normalizedText: "low",
      updatedAt: now.addingTimeInterval(100),
      usageCount: 1
    )
    let high = PromptItem(
      title: "High",
      plainText: "high",
      normalizedText: "high",
      updatedAt: now,
      usageCount: 3
    )

    let result = PromptSnapshot(items: [low, high], categories: [], tags: [], links: [])
      .result(sortOrder: .usageFrequency)
    XCTAssertEqual(result.items.map(\.id), [high.id, low.id])
  }

  func testSortsRecentlyUsedByLastUsedAt() {
    let now = Date()
    let old = PromptItem(
      title: "Old",
      plainText: "old",
      normalizedText: "old",
      lastUsedAt: now.addingTimeInterval(-10)
    )
    let recent = PromptItem(
      title: "Recent",
      plainText: "recent",
      normalizedText: "recent",
      lastUsedAt: now
    )

    let result = PromptSnapshot(items: [old, recent], categories: [], tags: [], links: [])
      .result(sortOrder: .recentlyUsed)
    XCTAssertEqual(result.items.map(\.id), [recent.id, old.id])
  }
}

final class PromptPerformanceTests: XCTestCase {
  func testSnapshotFiltering100Items() {
    measureSnapshotFiltering(itemCount: 100)
  }

  func testSnapshotFiltering1000Items() {
    measureSnapshotFiltering(itemCount: 1_000)
  }

  func testSnapshotFiltering10000Items() {
    measureSnapshotFiltering(itemCount: 10_000)
  }

  private func measureSnapshotFiltering(itemCount: Int) {
    let tag = PromptTag(name: "swift")
    let items = (0..<itemCount).map { index in
      PromptItem(
        title: "Prompt \(index)",
        plainText: "Text \(index)",
        normalizedText: "text \(index)"
      )
    }
    let links = items.map { PromptItemTagLink(promptItemID: $0.id, promptTagID: tag.id) }
    let snapshot = PromptSnapshot(items: items, categories: [], tags: [tag], links: links)

    measure {
      _ = snapshot.result(searchQuery: "#swift", sortOrder: .title)
    }
  }
}
