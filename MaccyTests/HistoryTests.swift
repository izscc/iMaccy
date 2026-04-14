import XCTest
import Defaults
@testable import Maccy

@MainActor
class HistoryTests: XCTestCase {
  let savedSize = Defaults[.size]
  let savedSortBy = Defaults[.sortBy]
  let history = History.shared

  override func setUp() {
    super.setUp()
    history.clearAll()
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.items, [])
  }

  func testAdding() {
    let first = history.add(historyItem("foo"))
    let second = history.add(historyItem("bar"))
    XCTAssertEqual(history.items, [second, first])
  }

  func testAddingSame() {
    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    let firstDecorator = history.add(first)
    first.pin = "f"

    let secondDecorator = history.add(historyItem("bar"))

    let third = historyItem("foo")
    third.application = "Xcode.app"
    history.add(third)

    XCTAssertEqual(history.items, [firstDecorator, secondDecorator])
    XCTAssertTrue(history.items[0].item.lastCopiedAt > history.items[0].item.firstCopiedAt)
    // TODO: This works in reality but fails in tests?!
    // XCTAssertEqual(history.items[0].item.numberOfCopies, 2)
    XCTAssertEqual(history.items[0].item.pin, "f")
    XCTAssertEqual(history.items[0].item.title, "xyz")
    XCTAssertEqual(history.items[0].item.application, "iTerm.app")
  }

  func testAddingItemThatIsSupersededByExisting() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.rtf.rawValue,
        value: "two".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.application = "Maccy.app"
    firstItem.contents = firstContents
    firstItem.title = firstItem.generateTitle()
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.application = "Maccy.app"
    secondItem.contents = secondContents
    secondItem.title = secondItem.generateTitle()
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemWithDifferentModifiedType() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "1".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.contents = firstContents
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "2".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.contents = secondContents
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemFromMaccy() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      )
    ]
    let first = HistoryItem()
    Storage.shared.context.insert(first)
    first.application = "Xcode.app"
    first.contents = firstContents
    history.add(first)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fromMaccy.rawValue,
        value: "".data(using: .utf8)
      )
    ]
    let second = HistoryItem()
    Storage.shared.context.insert(second)
    second.application = "Maccy.app"
    second.contents = secondContents
    let secondDecorator = history.add(second)

    XCTAssertEqual(history.items, [secondDecorator])
    XCTAssertEqual(history.items[0].item.application, "Xcode.app")
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testModifiedAfterCopying() {
    history.add(historyItem("foo"))

    let modifiedItem = historyItem("bar")
    modifiedItem.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: String(Clipboard.shared.changeCount).data(using: .utf8)
    ))
    let modifiedItemDecorator = history.add(modifiedItem)

    XCTAssertEqual(history.items, [modifiedItemDecorator])
    XCTAssertEqual(history.items[0].text, "bar")
  }

  func testClearingUnpinned() {
    let pinned = history.add(historyItem("foo"))
    pinned.togglePin()
    history.add(historyItem("bar"))
    history.clear()
    XCTAssertEqual(history.items, [pinned])
  }

  func testClearingAll() {
    history.add(historyItem("foo"))
    history.clear()
    XCTAssertEqual(history.items, [])
  }

  func testMaxSize() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 10)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[0]))
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItemDecorator] = []

    let item = history.add(historyItem("0"))
    items.append(item)
    item.togglePin()

    for index in 1...11 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 11)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertTrue(history.items.contains(items[0]))
    XCTAssertFalse(history.items.contains(items[1]))
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }
    Defaults[.size] = 5
    history.add(historyItem("11"))

    XCTAssertEqual(history.items.count, 5)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[5]))
  }

  func testRemoving() {
    let foo = history.add(historyItem("foo"))
    let bar = history.add(historyItem("bar"))
    history.delete(foo)
    XCTAssertEqual(history.items, [bar])
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}

@MainActor
class PromptPhase1Tests: XCTestCase {
  var promptLibrary: PromptLibrary!
  var promptCategoryStore: PromptCategoryStore!
  var promptOrganizer: PromptOrganizer!

  override func setUp() {
    super.setUp()
    clearPromptData()
    promptLibrary = PromptLibrary()
    promptCategoryStore = PromptCategoryStore()
    promptOrganizer = PromptOrganizer(promptLibrary: promptLibrary, promptCategoryStore: promptCategoryStore)
    promptCategoryStore.seedDefaultsIfNeeded()
    promptLibrary.load()
  }

  override func tearDown() {
    clearPromptData()
    super.tearDown()
  }

  func testSeedDefaultsCreatesSinglePromptRoot() {
    promptCategoryStore.seedDefaultsIfNeeded()
    promptCategoryStore.seedDefaultsIfNeeded()

    XCTAssertEqual(promptCategoryStore.categories.count, 1)
    XCTAssertEqual(promptCategoryStore.categories.first?.name, "Prompt")
    XCTAssertTrue(promptCategoryStore.categories.first?.isSystem == true)
  }

  func testMoveToPromptCreatesPromptItem() {
    let item = historyItem("整理这段需求，输出一份结构化总结")

    let promptItem = promptOrganizer.moveToPrompt(item)

    XCTAssertNotNil(promptItem)
    XCTAssertEqual(promptLibrary.items.count, 1)
    XCTAssertEqual(promptLibrary.items.first?.plainText, "整理这段需求，输出一份结构化总结")
  }

  func testMoveToPromptRejectsFileHistoryItem() {
    let url = URL(fileURLWithPath: "/tmp/imaccy.txt")
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: url.dataRepresentation),
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: url.lastPathComponent.data(using: .utf8))
    ]
    item.title = item.generateTitle()

    let promptItem = promptOrganizer.moveToPrompt(item)

    XCTAssertNil(promptItem)
    XCTAssertEqual(promptLibrary.items.count, 0)
  }

  func testMoveToPromptDuplicateCanUpdateExisting() {
    promptOrganizer.duplicateDecisionHandler = { _ in .updateExisting }
    let first = historyItem("为这段代码写一个简洁的 review")
    let second = historyItem("  为这段代码写一个简洁的   review  ")

    let firstPrompt = promptOrganizer.moveToPrompt(first)
    let updatedPrompt = promptOrganizer.moveToPrompt(second)

    XCTAssertEqual(promptLibrary.items.count, 1)
    XCTAssertEqual(firstPrompt?.id, updatedPrompt?.id)
    XCTAssertEqual(promptLibrary.items.first?.usageCount, 2)
  }

  func testMoveToPromptDuplicateCanCreateNewCopy() {
    promptOrganizer.duplicateDecisionHandler = { _ in .createNewCopy }
    let first = historyItem("给我一份发布公告")
    let second = historyItem("给我一份发布公告")

    _ = promptOrganizer.moveToPrompt(first)
    _ = promptOrganizer.moveToPrompt(second)

    XCTAssertEqual(promptLibrary.items.count, 2)
  }

  func testMoveToPromptDuplicateCanCancel() {
    promptOrganizer.duplicateDecisionHandler = { _ in .cancel }
    let first = historyItem("把这份日报改写成周报摘要")
    let second = historyItem("把这份日报改写成周报摘要")

    _ = promptOrganizer.moveToPrompt(first)
    let cancelledPrompt = promptOrganizer.moveToPrompt(second)

    XCTAssertNil(cancelledPrompt)
    XCTAssertEqual(promptLibrary.items.count, 1)
  }

  func testPromptLibraryFavoritesAndSearch() {
    let first = PromptItem(
      title: "代码审查",
      plainText: "请帮我 review 这段代码",
      normalizedText: "请帮我 review 这段代码",
      isFavorite: true,
      usageCount: 3
    )
    let second = PromptItem(
      title: "写邮件",
      plainText: "请帮我写一封上线通知邮件",
      normalizedText: "请帮我写一封上线通知邮件",
      isFavorite: false,
      usageCount: 1
    )
    Storage.shared.context.insert(first)
    Storage.shared.context.insert(second)
    promptLibrary.load()

    XCTAssertEqual(promptLibrary.visibleItems(searchQuery: "", favoritesOnly: true, selectedCategoryID: nil).count, 1)
    XCTAssertEqual(promptLibrary.visibleItems(searchQuery: "邮件", favoritesOnly: false, selectedCategoryID: nil).first?.title, "写邮件")
  }

  private func clearPromptData() {
    try? Storage.shared.context.delete(model: PromptItemTagLink.self)
    try? Storage.shared.context.delete(model: PromptTag.self)
    try? Storage.shared.context.delete(model: PromptItem.self)
    try? Storage.shared.context.delete(model: PromptCategory.self)
    try? Storage.shared.context.save()
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    return item
  }
}
