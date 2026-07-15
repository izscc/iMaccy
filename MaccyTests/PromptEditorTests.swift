import SwiftData
import XCTest

@testable import iMaccy

@MainActor
final class PromptEditorTests: XCTestCase {
  private var container: ModelContainer!
  private var context: ModelContext { container.mainContext }
  private var library: PromptLibrary!
  private var categories: PromptCategoryStore!
  private var tags: PromptTagStore!
  private var organizer: PromptOrganizer!

  override func setUpWithError() throws {
    container = try ModelContainer(
      for: PromptItem.self,
      PromptCategory.self,
      PromptTag.self,
      PromptItemTagLink.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    library = PromptLibrary(context: context)
    categories = PromptCategoryStore(context: context)
    tags = PromptTagStore(context: context)
    organizer = PromptOrganizer(
      promptLibrary: library,
      promptCategoryStore: categories,
      promptTagStore: tags
    )
    categories.seedDefaultsIfNeeded()
    tags.load()
    library.load()
  }

  func testCreateAndEditPrompt() throws {
    let rootID = try XCTUnwrap(categories.rootPromptCategory()?.id)
    let prompt = try library.create(title: "  Draft  ", plainText: "First body", categoryID: rootID)

    XCTAssertEqual(prompt.title, "Draft")
    XCTAssertEqual(prompt.usageCount, 0)

    try library.update(prompt, title: "Published", plainText: "Updated body")

    XCTAssertEqual(prompt.title, "Published")
    XCTAssertEqual(prompt.plainText, "Updated body")
    XCTAssertEqual(prompt.normalizedText, "updated body")
  }

  func testCreateRejectsEmptyFieldsWithoutPersistingPartialItem() throws {
    let rootID = try XCTUnwrap(categories.rootPromptCategory()?.id)

    XCTAssertThrowsError(try library.create(title: "", plainText: "Body", categoryID: rootID))
    XCTAssertThrowsError(try library.create(title: "Title", plainText: "   ", categoryID: rootID))
    XCTAssertTrue(library.items.isEmpty)
  }

  func testDuplicateCopiesCategoryAndTagsButResetsUsage() throws {
    let rootID = try XCTUnwrap(categories.rootPromptCategory()?.id)
    let prompt = try library.create(title: "Original", plainText: "Body", categoryID: rootID)
    let tag = try tags.createTag("shared")
    try organizer.setTagIDs([tag.id], for: prompt)
    try library.markUsed(prompt)

    let copy = try organizer.duplicatePrompt(prompt)

    XCTAssertNotEqual(copy.id, prompt.id)
    XCTAssertEqual(copy.categoryID, prompt.categoryID)
    XCTAssertEqual(copy.plainText, prompt.plainText)
    XCTAssertEqual(copy.usageCount, 0)
    XCTAssertNil(copy.lastUsedAt)
    XCTAssertEqual(tags.tagIDs(for: copy.id), Set([tag.id]))
  }
}
