import AppKit
import Observation
import SwiftData

enum LibraryScope: String, CaseIterable, Identifiable, Sendable {
  case history
  case prompt
  case favorites

  var id: Self { self }

  var title: String {
    switch self {
    case .history:
      return "历史"
    case .prompt:
      return "Prompt"
    case .favorites:
      return "常用"
    }
  }
}

enum PromptScope: Sendable {
  case prompt
  case favorites
}

enum PromptDuplicateResolution: Sendable {
  case updateExisting
  case createNewCopy
  case cancel
}

enum PromptDomainError: LocalizedError, Equatable {
  case emptyBookmarkName
  case duplicateBookmarkName
  case cannotDeleteSystemCategory
  case rootCategoryMissing
  case emptyTagName
  case duplicateTagName

  var errorDescription: String? {
    switch self {
    case .emptyBookmarkName:
      return "子书签名称不能为空。"
    case .duplicateBookmarkName:
      return "该子书签名称已存在。"
    case .cannotDeleteSystemCategory:
      return "系统 Prompt 根目录不能删除。"
    case .rootCategoryMissing:
      return "未找到 Prompt 根目录。"
    case .emptyTagName:
      return "标签名称不能为空。"
    case .duplicateTagName:
      return "该标签名称已存在。"
    }
  }
}

@MainActor
@Observable
class PromptFilterStateStore {
  var scope: PromptScope = .prompt
  var searchQuery: String = ""
  var selectedCategoryID: UUID?
  var selectedTagIDs: Set<UUID> = []
  var favoritesOnly: Bool = false
}

@MainActor
@Observable
class PromptCategoryStore {
  var categories: [PromptCategory] = []

  var bookmarkCategories: [PromptCategory] {
    guard let rootID = rootPromptCategory()?.id else { return [] }
    return categories.filter { $0.parentID == rootID }
  }

  func load() {
    let descriptor = FetchDescriptor<PromptCategory>()
    categories = (try? Storage.shared.context.fetch(descriptor))?.sorted {
      if $0.isSystem != $1.isSystem {
        return $0.isSystem && !$1.isSystem
      }
      if $0.sortOrder != $1.sortOrder {
        return $0.sortOrder < $1.sortOrder
      }
      return $0.name.localizedCompare($1.name) == .orderedAscending
    } ?? []
  }

  func seedDefaultsIfNeeded() {
    let descriptor = FetchDescriptor<PromptCategory>(
      predicate: #Predicate<PromptCategory> { $0.isSystem && $0.parentID == nil }
    )

    if (try? Storage.shared.context.fetch(descriptor).isEmpty) == false {
      load()
      return
    }

    let rootCategory = PromptCategory(
      name: "Prompt",
      parentID: nil,
      sortOrder: 0,
      isSystem: true,
      symbolName: "text.quote"
    )
    Storage.shared.context.insert(rootCategory)
    try? Storage.shared.context.save()
    load()
  }

  func rootPromptCategory() -> PromptCategory? {
    seedDefaultsIfNeeded()
    return categories.first(where: { $0.isSystem && $0.parentID == nil })
  }

  func isRootCategoryID(_ id: UUID?) -> Bool {
    guard let id, let rootID = rootPromptCategory()?.id else { return false }
    return id == rootID
  }

  func categoryName(for id: UUID?) -> String {
    guard let id else { return "Prompt" }
    return categories.first(where: { $0.id == id })?.name ?? "Prompt"
  }

  func createBookmark(_ name: String) throws -> PromptCategory {
    guard let root = rootPromptCategory() else {
      throw PromptDomainError.rootCategoryMissing
    }

    let validatedName = try validateBookmarkName(name)
    let nextSort = (bookmarkCategories.map(\.sortOrder).max() ?? -1) + 1
    let category = PromptCategory(
      name: validatedName,
      parentID: root.id,
      sortOrder: nextSort,
      isSystem: false,
      symbolName: "bookmark"
    )
    Storage.shared.context.insert(category)
    try Storage.shared.context.save()
    load()
    return category
  }

  func renameBookmark(_ category: PromptCategory, to name: String) throws {
    let validatedName = try validateBookmarkName(name, excluding: category)
    category.name = validatedName
    try Storage.shared.context.save()
    load()
  }

  func deleteBookmark(_ category: PromptCategory) throws {
    guard !category.isSystem else {
      throw PromptDomainError.cannotDeleteSystemCategory
    }
    guard let root = rootPromptCategory() else {
      throw PromptDomainError.rootCategoryMissing
    }

    let items = try Storage.shared.context.fetch(FetchDescriptor<PromptItem>())
    for item in items where item.categoryID == category.id {
      item.categoryID = root.id
      item.updatedAt = .now
    }

    Storage.shared.context.delete(category)
    try Storage.shared.context.save()
    load()
  }

  private func validateBookmarkName(_ name: String, excluding current: PromptCategory? = nil) throws -> String {
    let trimmed = name.promptTrimmedName
    let normalized = name.promptNormalizedName

    guard !trimmed.isEmpty else {
      throw PromptDomainError.emptyBookmarkName
    }

    let duplicate = bookmarkCategories.contains { category in
      if let current, current.id == category.id {
        return false
      }
      return category.name.promptNormalizedName == normalized
    }

    if duplicate {
      throw PromptDomainError.duplicateBookmarkName
    }

    return trimmed
  }
}

@MainActor
@Observable
class PromptTagStore {
  var tags: [PromptTag] = []
  var links: [PromptItemTagLink] = []

  func load() {
    tags = (try? Storage.shared.context.fetch(FetchDescriptor<PromptTag>()))?.sorted {
      $0.name.localizedCompare($1.name) == .orderedAscending
    } ?? []
    links = (try? Storage.shared.context.fetch(FetchDescriptor<PromptItemTagLink>())) ?? []
  }

  func tagIDs(for promptItemID: UUID) -> Set<UUID> {
    Set(links.filter { $0.promptItemID == promptItemID }.map(\.promptTagID))
  }

  func tags(for promptItemID: UUID) -> [PromptTag] {
    let ids = tagIDs(for: promptItemID)
    return tags.filter { ids.contains($0.id) }
  }

  func hasAllTags(promptItemID: UUID, selectedTagIDs: Set<UUID>) -> Bool {
    guard !selectedTagIDs.isEmpty else { return true }
    return selectedTagIDs.isSubset(of: tagIDs(for: promptItemID))
  }

  func createTag(_ name: String) throws -> PromptTag {
    let validatedName = try validateTagName(name)
    let tag = PromptTag(name: validatedName)
    Storage.shared.context.insert(tag)
    try Storage.shared.context.save()
    load()
    return tag
  }

  func findOrCreateTag(_ name: String) throws -> PromptTag {
    let trimmed = name.promptTrimmedName
    let normalized = name.promptNormalizedName

    guard !trimmed.isEmpty else {
      throw PromptDomainError.emptyTagName
    }

    if let existing = tags.first(where: { $0.name.promptNormalizedName == normalized }) {
      return existing
    }

    return try createTag(trimmed)
  }

  func renameTag(_ tag: PromptTag, to name: String) throws {
    let validatedName = try validateTagName(name, excluding: tag)
    tag.name = validatedName
    try Storage.shared.context.save()
    load()
  }

  func deleteTag(_ tag: PromptTag) {
    let relatedLinks = links.filter { $0.promptTagID == tag.id }
    for link in relatedLinks {
      Storage.shared.context.delete(link)
    }
    Storage.shared.context.delete(tag)
    try? Storage.shared.context.save()
    load()
  }

  func setTagIDs(_ tagIDs: Set<UUID>, for promptItemID: UUID) {
    let currentLinks = links.filter { $0.promptItemID == promptItemID }
    let currentIDs = Set(currentLinks.map(\.promptTagID))

    for link in currentLinks where !tagIDs.contains(link.promptTagID) {
      Storage.shared.context.delete(link)
    }

    let toInsert = tagIDs.subtracting(currentIDs)
    for tagID in toInsert {
      Storage.shared.context.insert(PromptItemTagLink(promptItemID: promptItemID, promptTagID: tagID))
    }

    try? Storage.shared.context.save()
    load()
  }

  private func validateTagName(_ name: String, excluding current: PromptTag? = nil) throws -> String {
    let trimmed = name.promptTrimmedName
    let normalized = name.promptNormalizedName

    guard !trimmed.isEmpty else {
      throw PromptDomainError.emptyTagName
    }

    let duplicate = tags.contains { tag in
      if let current, current.id == tag.id {
        return false
      }
      return tag.name.promptNormalizedName == normalized
    }

    if duplicate {
      throw PromptDomainError.duplicateTagName
    }

    return trimmed
  }
}

@MainActor
@Observable
class PromptLibrary {
  var items: [PromptItem] = []

  func load() {
    items = sorted((try? Storage.shared.context.fetch(FetchDescriptor<PromptItem>())) ?? [])
  }

  func visibleItems(
    searchQuery: String,
    favoritesOnly: Bool,
    selectedCategoryID: UUID?,
    selectedTagIDs: Set<UUID>,
    tagStore: PromptTagStore
  ) -> [PromptItem] {
    let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    return items.filter { item in
      if favoritesOnly && !item.isFavorite {
        return false
      }

      if let selectedCategoryID, item.categoryID != selectedCategoryID {
        return false
      }

      if !tagStore.hasAllTags(promptItemID: item.id, selectedTagIDs: selectedTagIDs) {
        return false
      }

      guard !trimmedQuery.isEmpty else {
        return true
      }

      return item.title.localizedCaseInsensitiveContains(trimmedQuery) ||
        item.plainText.localizedCaseInsensitiveContains(trimmedQuery)
    }
  }

  func findDuplicate(normalizedText: String) -> PromptItem? {
    let descriptor = FetchDescriptor<PromptItem>(
      predicate: #Predicate<PromptItem> { $0.normalizedText == normalizedText }
    )
    return try? Storage.shared.context.fetch(descriptor).first
  }

  func toggleFavorite(_ item: PromptItem) {
    item.isFavorite.toggle()
    item.updatedAt = .now
    try? Storage.shared.context.save()
    load()
  }

  func delete(_ item: PromptItem) {
    Storage.shared.context.delete(item)
    try? Storage.shared.context.save()
    load()
  }

  func markUsed(_ item: PromptItem) {
    item.usageCount += 1
    item.updatedAt = .now
    try? Storage.shared.context.save()
    load()
  }

  private func sorted(_ items: [PromptItem]) -> [PromptItem] {
    items.sorted {
      if $0.isFavorite != $1.isFavorite {
        return $0.isFavorite && !$1.isFavorite
      }
      if $0.updatedAt != $1.updatedAt {
        return $0.updatedAt > $1.updatedAt
      }
      return $0.createdAt > $1.createdAt
    }
  }
}

@MainActor
@Observable
class PromptOrganizer {
  let promptLibrary: PromptLibrary
  let promptCategoryStore: PromptCategoryStore
  let promptTagStore: PromptTagStore

  @ObservationIgnored
  var duplicateDecisionHandler: (PromptItem) -> PromptDuplicateResolution = { existing in
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "已存在相似 Prompt"
    alert.informativeText = "“\(existing.title)” 已经在 Prompt 中。你可以更新已有 Prompt，或新建一份副本。"
    alert.addButton(withTitle: "更新已有 Prompt")
    alert.addButton(withTitle: "新建副本")
    alert.addButton(withTitle: "取消")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return .updateExisting
    case .alertSecondButtonReturn:
      return .createNewCopy
    default:
      return .cancel
    }
  }

  init(promptLibrary: PromptLibrary, promptCategoryStore: PromptCategoryStore, promptTagStore: PromptTagStore) {
    self.promptLibrary = promptLibrary
    self.promptCategoryStore = promptCategoryStore
    self.promptTagStore = promptTagStore
  }

  func canArchive(_ historyItem: HistoryItem) -> Bool {
    historyItem.promptPlainText != nil
  }

  func moveToPrompt(_ historyItem: HistoryItem, targetCategoryID: UUID? = nil) -> PromptItem? {
    guard let plainText = historyItem.promptPlainText,
          let targetCategoryID = resolvedCategoryID(targetCategoryID) else {
      return nil
    }

    let normalizedText = plainText.promptNormalizedText
    if let existingPrompt = promptLibrary.findDuplicate(normalizedText: normalizedText) {
      switch duplicateDecisionHandler(existingPrompt) {
      case .updateExisting:
        existingPrompt.title = plainText.promptDisplayTitle
        existingPrompt.plainText = plainText
        existingPrompt.normalizedText = normalizedText
        existingPrompt.updatedAt = .now
        existingPrompt.usageCount += 1
        existingPrompt.categoryID = targetCategoryID
        existingPrompt.sourceHistoryItemID = String(describing: historyItem.persistentModelID)
        try? Storage.shared.context.save()
        promptLibrary.load()
        return existingPrompt
      case .createNewCopy:
        break
      case .cancel:
        return nil
      }
    }

    let promptItem = PromptItem(
      title: plainText.promptDisplayTitle,
      plainText: plainText,
      normalizedText: normalizedText,
      isFavorite: false,
      createdAt: .now,
      updatedAt: .now,
      usageCount: 1,
      sourceHistoryItemID: String(describing: historyItem.persistentModelID),
      categoryID: targetCategoryID
    )
    Storage.shared.context.insert(promptItem)
    try? Storage.shared.context.save()
    promptLibrary.load()
    return promptItem
  }

  func assignPrompt(_ promptItem: PromptItem, to categoryID: UUID?) {
    guard let resolvedCategoryID = resolvedCategoryID(categoryID) else {
      return
    }

    promptItem.categoryID = resolvedCategoryID
    promptItem.updatedAt = .now
    try? Storage.shared.context.save()
    promptLibrary.load()
  }

  func setTagIDs(_ tagIDs: Set<UUID>, for promptItem: PromptItem) {
    promptTagStore.setTagIDs(tagIDs, for: promptItem.id)
    promptItem.updatedAt = .now
    try? Storage.shared.context.save()
    promptLibrary.load()
  }

  func removeTag(_ tag: PromptTag, from promptItem: PromptItem) {
    var ids = promptTagStore.tagIDs(for: promptItem.id)
    ids.remove(tag.id)
    setTagIDs(ids, for: promptItem)
  }

  private func resolvedCategoryID(_ categoryID: UUID?) -> UUID? {
    if let categoryID {
      return categoryID
    }
    return promptCategoryStore.rootPromptCategory()?.id
  }
}
