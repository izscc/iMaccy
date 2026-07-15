import SwiftData
import XCTest

@testable import iMaccy

@MainActor
final class PromptIntegrityTests: XCTestCase {
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

  func testRepairRemovesOrphansAndIsIdempotent() throws {
    let rootID = try XCTUnwrap(categories.rootPromptCategory()?.id)
    let prompt = PromptItem(
      title: "Repair",
      plainText: "Repair this Prompt",
      normalizedText: "repair this prompt",
      categoryID: UUID()
    )
    let tag = PromptTag(name: "valid")
    context.insert(prompt)
    context.insert(tag)
    context.insert(PromptItemTagLink(promptItemID: prompt.id, promptTagID: tag.id))
    context.insert(PromptItemTagLink(promptItemID: prompt.id, promptTagID: tag.id))
    context.insert(PromptItemTagLink(promptItemID: UUID(), promptTagID: tag.id))
    context.insert(PromptItemTagLink(promptItemID: prompt.id, promptTagID: UUID()))
    try context.save()

    let first = try PromptIntegrityRepair.run(context: context, rootCategoryID: rootID)
    XCTAssertEqual(first.removedOrphanLinks, 2)
    XCTAssertEqual(first.removedDuplicateLinks, 1)
    XCTAssertEqual(first.repairedPromptCategories, 1)
    XCTAssertEqual(prompt.categoryID, rootID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<PromptItemTagLink>()).count, 1)

    let second = try PromptIntegrityRepair.run(context: context, rootCategoryID: rootID)
    XCTAssertEqual(second.changeCount, 0)
  }

  func testWritesRejectInvalidCategoryAndTagIDs() throws {
    let prompt = try library.create(
      title: "Validation",
      plainText: "Validate references",
      categoryID: categories.rootPromptCategory()?.id
    )
    tags.load()

    XCTAssertThrowsError(try organizer.assignPrompt(prompt, to: UUID())) { error in
      XCTAssertEqual(error as? PromptDomainError, .invalidCategoryID)
    }
    XCTAssertThrowsError(try organizer.setTagIDs([UUID()], for: prompt)) { error in
      XCTAssertEqual(error as? PromptDomainError, .invalidTagIDs)
    }
  }

  func testDeletingPromptAlsoDeletesTagLinks() throws {
    let prompt = try library.create(
      title: "Delete",
      plainText: "Delete this Prompt",
      categoryID: categories.rootPromptCategory()?.id
    )
    let tag = try tags.createTag("cleanup")
    try organizer.setTagIDs([tag.id], for: prompt)

    try organizer.deletePrompts([prompt])

    XCTAssertTrue(library.items.isEmpty)
    XCTAssertTrue(tags.links.isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PromptItemTagLink>()).isEmpty)
  }

  func testUsageChangesOnlyWhenMarkedUsed() throws {
    let prompt = try library.create(
      title: "Usage",
      plainText: "Track real usage",
      categoryID: categories.rootPromptCategory()?.id
    )
    XCTAssertEqual(prompt.usageCount, 0)
    XCTAssertNil(prompt.lastUsedAt)

    try library.markUsed(prompt)

    XCTAssertEqual(prompt.usageCount, 1)
    XCTAssertNotNil(prompt.lastUsedAt)
  }

  func testDuplicateSelectionIsDeterministic() throws {
    let sourceID = "source-1"
    let older = PromptItem(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      title: "Older",
      plainText: "same",
      normalizedText: "same",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    let sourceMatch = PromptItem(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      title: "Source",
      plainText: "same",
      normalizedText: "same",
      createdAt: Date(timeIntervalSince1970: 2),
      sourceHistoryItemID: sourceID
    )
    context.insert(older)
    context.insert(sourceMatch)
    try context.save()
    library.load()

    XCTAssertEqual(
      library.findDuplicate(normalizedText: "same", sourceHistoryItemID: sourceID)?.id,
      sourceMatch.id)
    XCTAssertEqual(
      library.findDuplicate(normalizedText: "same", sourceHistoryItemID: nil)?.id, older.id)
  }
}
