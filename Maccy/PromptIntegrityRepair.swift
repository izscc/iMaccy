import Foundation
import SwiftData

struct PromptIntegrityRepairReport: Equatable {
  var removedOrphanLinks = 0
  var removedDuplicateLinks = 0
  var repairedPromptCategories = 0
  var repairedCategoryParents = 0

  var changeCount: Int {
    removedOrphanLinks + removedDuplicateLinks + repairedPromptCategories + repairedCategoryParents
  }
}

@MainActor
enum PromptIntegrityRepair {
  static func run(context: ModelContext, rootCategoryID: UUID) throws -> PromptIntegrityRepairReport
  {
    let prompts = try context.fetch(FetchDescriptor<PromptItem>())
    let categories = try context.fetch(FetchDescriptor<PromptCategory>())
    let tags = try context.fetch(FetchDescriptor<PromptTag>())
    let links = try context.fetch(FetchDescriptor<PromptItemTagLink>())

    guard
      categories.contains(where: {
        $0.id == rootCategoryID && $0.isSystem && $0.parentID == nil
      })
    else {
      throw PromptDomainError.invalidCategoryID
    }

    let promptIDs = Set(prompts.map(\.id))
    let categoryIDs = Set(categories.map(\.id))
    let tagIDs = Set(tags.map(\.id))
    var seenLinks = Set<PromptLinkKey>()
    var report = PromptIntegrityRepairReport()

    for prompt in prompts {
      guard let categoryID = prompt.categoryID, categoryIDs.contains(categoryID) else {
        prompt.categoryID = rootCategoryID
        prompt.updatedAt = .now
        report.repairedPromptCategories += 1
        continue
      }
    }

    for category in categories where !category.isSystem && category.parentID != rootCategoryID {
      category.parentID = rootCategoryID
      report.repairedCategoryParents += 1
    }

    for link in links {
      guard promptIDs.contains(link.promptItemID), tagIDs.contains(link.promptTagID) else {
        context.delete(link)
        report.removedOrphanLinks += 1
        continue
      }

      let key = PromptLinkKey(promptItemID: link.promptItemID, promptTagID: link.promptTagID)
      guard seenLinks.insert(key).inserted else {
        context.delete(link)
        report.removedDuplicateLinks += 1
        continue
      }
    }

    if report.changeCount > 0 {
      do {
        try context.save()
      } catch {
        context.rollback()
        throw error
      }
    }
    return report
  }
}

private struct PromptLinkKey: Hashable {
  let promptItemID: UUID
  let promptTagID: UUID
}
