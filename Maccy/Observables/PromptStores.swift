import AppKit
import Defaults
import Observation
import SwiftData

enum LibraryScope: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
  case history
  case prompt
  case favorites

  var id: Self { self }

  var title: String {
    switch self {
    case .history:
      return NSLocalizedString("History", comment: "Library scope")
    case .prompt:
      return "Prompt"
    case .favorites:
      return NSLocalizedString("Favorites", comment: "Library scope")
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
  case invalidTagName
  case invalidCategoryID
  case invalidTagIDs
  case invalidPromptID
  case emptyPromptTitle
  case emptyPromptBody

  var errorDescription: String? {
    switch self {
    case .emptyBookmarkName:
      return NSLocalizedString("Bookmark name cannot be empty.", comment: "Prompt error")
    case .duplicateBookmarkName:
      return NSLocalizedString("A bookmark with this name already exists.", comment: "Prompt error")
    case .cannotDeleteSystemCategory:
      return NSLocalizedString("The Prompt root cannot be deleted.", comment: "Prompt error")
    case .rootCategoryMissing:
      return NSLocalizedString("The Prompt root could not be found.", comment: "Prompt error")
    case .emptyTagName:
      return NSLocalizedString("Tag name cannot be empty.", comment: "Prompt error")
    case .duplicateTagName:
      return NSLocalizedString("A tag with this name already exists.", comment: "Prompt error")
    case .invalidTagName:
      return NSLocalizedString("Tag names cannot contain line breaks.", comment: "Prompt error")
    case .invalidCategoryID:
      return NSLocalizedString("The selected Prompt category does not exist.", comment: "Prompt error")
    case .invalidTagIDs:
      return NSLocalizedString("One or more selected Prompt tags do not exist.", comment: "Prompt error")
    case .invalidPromptID:
      return NSLocalizedString("The selected Prompt does not exist.", comment: "Prompt error")
    case .emptyPromptTitle:
      return NSLocalizedString("Prompt title cannot be empty.", comment: "Prompt error")
    case .emptyPromptBody:
      return NSLocalizedString("Prompt body cannot be empty.", comment: "Prompt error")
    }
  }
}

@MainActor
@Observable
class PromptFilterStateStore {
  var scope: PromptScope = .prompt
  var searchQuery: String = ""
  var categoryFilter: PromptCategoryFilter = .all
  var selectedTagIDs: Set<UUID> = []
  var favoritesOnly: Bool = false
  var sortOrder: PromptSortOrder = .recentlyUpdated
}

@MainActor
@Observable
class PromptCategoryStore {
  var categories: [PromptCategory] = []
  var loadErrorMessage: String?

  @ObservationIgnored
  let context: ModelContext

  init(context: ModelContext? = nil) {
    self.context = context ?? Storage.shared.context
  }

  var bookmarkCategories: [PromptCategory] {
    guard let rootID = rootPromptCategory()?.id else { return [] }
    return categories.filter { $0.parentID == rootID }
  }

  func load() {
    let descriptor = FetchDescriptor<PromptCategory>()
    do {
      categories = try context.fetch(descriptor).sorted {
        if $0.isSystem != $1.isSystem {
          return $0.isSystem && !$1.isSystem
        }
        if $0.sortOrder != $1.sortOrder {
          return $0.sortOrder < $1.sortOrder
        }
        return $0.name.localizedCompare($1.name) == .orderedAscending
      }
      loadErrorMessage = nil
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }

  func seedDefaultsIfNeeded() {
    let descriptor = FetchDescriptor<PromptCategory>(
      predicate: #Predicate<PromptCategory> { $0.isSystem && $0.parentID == nil }
    )

    do {
      let existingRoots = try context.fetch(descriptor)
      if !existingRoots.isEmpty {
        load()
        return
      }
    } catch {
      loadErrorMessage = error.localizedDescription
      return
    }

    let rootCategory = PromptCategory(
      name: "Prompt",
      parentID: nil,
      sortOrder: 0,
      isSystem: true,
      symbolName: "text.quote"
    )
    context.insert(rootCategory)
    do {
      try context.save()
    } catch {
      context.rollback()
      loadErrorMessage = error.localizedDescription
      return
    }
    load()
  }

  func rootPromptCategory() -> PromptCategory? {
    return categories.first(where: { $0.isSystem && $0.parentID == nil })
  }

  func recentBookmarks(limit: Int = 3) -> [PromptCategory] {
    bookmarkCategories
      .filter { $0.lastAssignedAt != nil }
      .sorted {
        if $0.lastAssignedAt != $1.lastAssignedAt {
          return ($0.lastAssignedAt ?? .distantPast) > ($1.lastAssignedAt ?? .distantPast)
        }
        if $0.sortOrder != $1.sortOrder {
          return $0.sortOrder < $1.sortOrder
        }
        return $0.name.localizedCompare($1.name) == .orderedAscending
      }
      .prefix(limit)
      .map { $0 }
  }

  func markAssigned(_ categoryID: UUID?) {
    guard let categoryID,
          let category = categories.first(where: { $0.id == categoryID && !$0.isSystem }) else {
      return
    }

    category.lastAssignedAt = .now
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
    context.insert(category)
    try saveAndReload()
    return category
  }

  func renameBookmark(_ category: PromptCategory, to name: String) throws {
    let validatedName = try validateBookmarkName(name, excluding: category)
    category.name = validatedName
    try saveAndReload()
  }

  func deleteBookmark(_ category: PromptCategory) throws {
    guard !category.isSystem else {
      throw PromptDomainError.cannotDeleteSystemCategory
    }
    guard let root = rootPromptCategory() else {
      throw PromptDomainError.rootCategoryMissing
    }

    let items = try context.fetch(FetchDescriptor<PromptItem>())
    for item in items where item.categoryID == category.id {
      item.categoryID = root.id
      item.updatedAt = .now
    }

    context.delete(category)
    try saveAndReload()
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

  private func saveAndReload() throws {
    do {
      try context.save()
      load()
    } catch {
      context.rollback()
      load()
      throw error
    }
  }
}

@MainActor
@Observable
class PromptTagStore {
  var tags: [PromptTag] = []
  var links: [PromptItemTagLink] = []
  var loadErrorMessage: String?

  @ObservationIgnored
  private(set) var tagByID: [UUID: PromptTag] = [:]
  @ObservationIgnored
  private(set) var tagIDsByPromptID: [UUID: Set<UUID>] = [:]
  @ObservationIgnored
  private(set) var tagsByPromptID: [UUID: [PromptTag]] = [:]
  @ObservationIgnored
  let context: ModelContext

  init(context: ModelContext? = nil) {
    self.context = context ?? Storage.shared.context
  }

  func load() {
    do {
      tags = try context.fetch(FetchDescriptor<PromptTag>()).sorted {
        $0.name.localizedCompare($1.name) == .orderedAscending
      }
      links = try context.fetch(FetchDescriptor<PromptItemTagLink>())
      loadErrorMessage = nil
      rebuildIndexes()
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }

  func tagIDs(for promptItemID: UUID) -> Set<UUID> {
    tagIDsByPromptID[promptItemID] ?? []
  }

  func tags(for promptItemID: UUID) -> [PromptTag] {
    tagsByPromptID[promptItemID] ?? []
  }

  func hasAllTags(promptItemID: UUID, selectedTagIDs: Set<UUID>) -> Bool {
    guard !selectedTagIDs.isEmpty else { return true }
    return selectedTagIDs.isSubset(of: tagIDs(for: promptItemID))
  }

  func createTag(_ name: String) throws -> PromptTag {
    let validatedName = try validateTagName(name)
    let tag = PromptTag(name: validatedName)
    context.insert(tag)
    try saveAndReload()
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
    try saveAndReload()
  }

  func deleteTag(_ tag: PromptTag) throws {
    let relatedLinks = links.filter { $0.promptTagID == tag.id }
    for link in relatedLinks {
      context.delete(link)
    }
    context.delete(tag)
    try saveAndReload()
  }

  func setTagIDs(_ tagIDs: Set<UUID>, for promptItemID: UUID) throws {
    let promptIDs = Set(try context.fetch(FetchDescriptor<PromptItem>()).map(\.id))
    try applyTagIDs(tagIDs, for: promptItemID, validPromptIDs: promptIDs)
    do {
      try context.save()
      load()
    } catch {
      context.rollback()
      load()
      throw error
    }
  }

  func applyTagIDs(
    _ tagIDs: Set<UUID>,
    for promptItemID: UUID,
    validPromptIDs: Set<UUID>
  ) throws {
    guard validPromptIDs.contains(promptItemID) else {
      throw PromptDomainError.invalidPromptID
    }
    guard tagIDs.isSubset(of: Set(tags.map(\.id))) else {
      throw PromptDomainError.invalidTagIDs
    }

    let currentLinks = links.filter { $0.promptItemID == promptItemID }
    let currentIDs = Set(currentLinks.map(\.promptTagID))

    for link in currentLinks where !tagIDs.contains(link.promptTagID) {
      context.delete(link)
      links.removeAll { $0.id == link.id }
    }

    let toInsert = tagIDs.subtracting(currentIDs)
    for tagID in toInsert {
      let link = PromptItemTagLink(promptItemID: promptItemID, promptTagID: tagID)
      context.insert(link)
      links.append(link)
    }
    rebuildIndexes()
  }

  private func validateTagName(_ name: String, excluding current: PromptTag? = nil) throws -> String {
    let trimmed = name.promptTrimmedName
    let normalized = name.promptNormalizedName

    guard !trimmed.isEmpty else {
      throw PromptDomainError.emptyTagName
    }
    guard !trimmed.contains(where: \.isNewline) else {
      throw PromptDomainError.invalidTagName
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

  private func rebuildIndexes() {
    tagByID = tags.reduce(into: [:]) { result, tag in
      result[tag.id] = tag
    }
    tagIDsByPromptID = Dictionary(grouping: links, by: \.promptItemID)
      .mapValues { Set($0.map(\.promptTagID)) }
    tagsByPromptID = tagIDsByPromptID.mapValues { ids in
      ids.compactMap { tagByID[$0] }.sorted {
        $0.name.localizedCompare($1.name) == .orderedAscending
      }
    }
  }

  private func saveAndReload() throws {
    do {
      try context.save()
      load()
    } catch {
      context.rollback()
      load()
      throw error
    }
  }
}

@MainActor
@Observable
class PromptLibrary {
  var items: [PromptItem] = []
  var loadErrorMessage: String?

  @ObservationIgnored
  let context: ModelContext

  init(context: ModelContext? = nil) {
    self.context = context ?? Storage.shared.context
  }

  func load() {
    do {
      items = sorted(try context.fetch(FetchDescriptor<PromptItem>()))
      loadErrorMessage = nil
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }

  func findDuplicate(normalizedText: String, sourceHistoryItemID: String?) -> PromptItem? {
    items
      .filter { $0.normalizedText == normalizedText }
      .sorted { lhs, rhs in
        let lhsMatchesSource = sourceHistoryItemID != nil && lhs.sourceHistoryItemID == sourceHistoryItemID
        let rhsMatchesSource = sourceHistoryItemID != nil && rhs.sourceHistoryItemID == sourceHistoryItemID
        if lhsMatchesSource != rhsMatchesSource {
          return lhsMatchesSource
        }
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .first
  }

  func create(title: String, plainText: String, categoryID: UUID?) throws -> PromptItem {
    let title = try validatedTitle(title)
    let plainText = try validatedBody(plainText)
    try validateCategoryID(categoryID)

    let item = PromptItem(
      title: title,
      plainText: plainText,
      normalizedText: plainText.promptNormalizedText,
      usageCount: 0,
      categoryID: categoryID
    )
    context.insert(item)
    try saveAndReload()
    return item
  }

  func update(_ item: PromptItem, title: String, plainText: String) throws {
    guard items.contains(where: { $0.id == item.id }) else {
      throw PromptDomainError.invalidPromptID
    }
    item.title = try validatedTitle(title)
    item.plainText = try validatedBody(plainText)
    item.normalizedText = item.plainText.promptNormalizedText
    item.updatedAt = .now
    try saveAndReload()
  }

  func toggleFavorite(_ item: PromptItem) throws {
    item.isFavorite.toggle()
    item.updatedAt = .now
    try saveAndReload()
  }

  func delete(_ item: PromptItem) throws {
    try delete([item])
  }

  func delete(_ itemsToDelete: [PromptItem]) throws {
    let itemIDs = Set(itemsToDelete.map(\.id))
    let links = try context.fetch(FetchDescriptor<PromptItemTagLink>())
    for link in links where itemIDs.contains(link.promptItemID) {
      context.delete(link)
    }
    for item in itemsToDelete {
      context.delete(item)
    }
    try saveAndReload()
  }

  func markUsed(_ item: PromptItem) throws {
    item.usageCount += 1
    item.lastUsedAt = .now
    try saveAndReload()
  }

  func setFavorite(_ value: Bool, for itemsToUpdate: [PromptItem]) throws {
    for item in itemsToUpdate {
      item.isFavorite = value
      item.updatedAt = .now
    }
    try saveAndReload()
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

  private func validatedTitle(_ title: String) throws -> String {
    let trimmed = title.promptTrimmedName
    guard !trimmed.isEmpty else { throw PromptDomainError.emptyPromptTitle }
    return trimmed
  }

  private func validatedBody(_ body: String) throws -> String {
    guard !body.promptTrimmedName.isEmpty else { throw PromptDomainError.emptyPromptBody }
    return body
  }

  private func validateCategoryID(_ categoryID: UUID?) throws {
    guard let categoryID else { return }
    let categoryIDs = Set(try context.fetch(FetchDescriptor<PromptCategory>()).map(\.id))
    guard categoryIDs.contains(categoryID) else { throw PromptDomainError.invalidCategoryID }
  }

  private func saveAndReload() throws {
    do {
      try context.save()
      load()
    } catch {
      context.rollback()
      load()
      throw error
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
    alert.messageText = NSLocalizedString("Similar Prompt Found", comment: "Duplicate Prompt alert")
    alert.informativeText = String(
      format: NSLocalizedString("The Prompt \"%@\" already exists. Update it or create a copy.", comment: "Duplicate Prompt alert"),
      existing.title
    )
    alert.addButton(withTitle: NSLocalizedString("Update Existing Prompt", comment: "Duplicate Prompt alert"))
    alert.addButton(withTitle: NSLocalizedString("Create Copy", comment: "Duplicate Prompt alert"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Duplicate Prompt alert"))

    let parentPanel = AppState.shared.appDelegate?.panel
    if let parentPanel {
      parentPanel.addChildWindow(alert.window, ordered: .above)
    }
    defer {
      if let parentPanel {
        parentPanel.removeChildWindow(alert.window)
      }
    }

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

  func duplicatePrompt(_ item: PromptItem) throws -> PromptItem {
    try validatePromptItems([item])
    let copy = PromptItem(
      title: String(format: NSLocalizedString("%@ Copy", comment: "Prompt duplicate title"), item.title),
      plainText: item.plainText,
      normalizedText: item.normalizedText,
      isFavorite: item.isFavorite,
      usageCount: 0,
      categoryID: item.categoryID
    )
    promptLibrary.context.insert(copy)
    let validPromptIDs = Set(promptLibrary.items.map(\.id)).union([copy.id])
    try promptTagStore.applyTagIDs(
      promptTagStore.tagIDs(for: item.id),
      for: copy.id,
      validPromptIDs: validPromptIDs
    )
    try saveAndReload()
    return copy
  }

  func moveToPrompt(_ historyItem: HistoryItem, targetCategoryID: UUID? = nil) throws -> PromptItem? {
    guard let plainText = historyItem.promptPlainText else {
      return nil
    }
    let targetCategoryID = try resolvedCategoryID(targetCategoryID)
    let sourceHistoryItemID = String(describing: historyItem.persistentModelID)

    let normalizedText = plainText.promptNormalizedText
    if let existingPrompt = promptLibrary.findDuplicate(
      normalizedText: normalizedText,
      sourceHistoryItemID: sourceHistoryItemID
    ) {
      switch duplicateDecisionHandler(existingPrompt) {
      case .updateExisting:
        existingPrompt.title = plainText.promptDisplayTitle
        existingPrompt.plainText = plainText
        existingPrompt.normalizedText = normalizedText
        existingPrompt.updatedAt = .now
        existingPrompt.categoryID = targetCategoryID
        existingPrompt.sourceHistoryItemID = sourceHistoryItemID
        promptCategoryStore.markAssigned(targetCategoryID)
        try saveAndReload()
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
      usageCount: 0,
      sourceHistoryItemID: sourceHistoryItemID,
      categoryID: targetCategoryID
    )
    promptLibrary.context.insert(promptItem)
    promptCategoryStore.markAssigned(targetCategoryID)
    try saveAndReload()
    return promptItem
  }

  func assignPrompt(_ promptItem: PromptItem, to categoryID: UUID?) throws {
    try assignPrompts([promptItem], to: categoryID)
  }

  func assignPrompts(_ promptItems: [PromptItem], to categoryID: UUID?) throws {
    let resolvedCategoryID = try resolvedCategoryID(categoryID)
    try validatePromptItems(promptItems)

    for item in promptItems {
      item.categoryID = resolvedCategoryID
      item.updatedAt = .now
    }
    promptCategoryStore.markAssigned(resolvedCategoryID)
    try saveAndReload()
  }

  func setTagIDs(_ tagIDs: Set<UUID>, for promptItem: PromptItem) throws {
    try validatePromptItems([promptItem])
    let validPromptIDs = Set(promptLibrary.items.map(\.id))
    try promptTagStore.applyTagIDs(tagIDs, for: promptItem.id, validPromptIDs: validPromptIDs)
    promptItem.updatedAt = .now
    try saveAndReload()
  }

  func addTags(_ tagIDs: Set<UUID>, to promptItems: [PromptItem]) throws {
    try validatePromptItems(promptItems)
    let validPromptIDs = Set(promptLibrary.items.map(\.id))
    for item in promptItems {
      let merged = promptTagStore.tagIDs(for: item.id).union(tagIDs)
      try promptTagStore.applyTagIDs(merged, for: item.id, validPromptIDs: validPromptIDs)
      item.updatedAt = .now
    }
    try saveAndReload()
  }

  func removeTags(_ tagIDs: Set<UUID>, from promptItems: [PromptItem]) throws {
    try validatePromptItems(promptItems)
    let validPromptIDs = Set(promptLibrary.items.map(\.id))
    for item in promptItems {
      let remained = promptTagStore.tagIDs(for: item.id).subtracting(tagIDs)
      try promptTagStore.applyTagIDs(remained, for: item.id, validPromptIDs: validPromptIDs)
      item.updatedAt = .now
    }
    try saveAndReload()
  }

  func setFavorite(_ value: Bool, for promptItems: [PromptItem]) throws {
    try validatePromptItems(promptItems)
    try promptLibrary.setFavorite(value, for: promptItems)
    promptCategoryStore.load()
    promptTagStore.load()
  }

  func deletePrompts(_ promptItems: [PromptItem]) throws {
    try validatePromptItems(promptItems)
    try promptLibrary.delete(promptItems)
    promptCategoryStore.load()
    promptTagStore.load()
  }

  func removeTag(_ tag: PromptTag, from promptItem: PromptItem) throws {
    var ids = promptTagStore.tagIDs(for: promptItem.id)
    ids.remove(tag.id)
    try setTagIDs(ids, for: promptItem)
  }

  private func resolvedCategoryID(_ categoryID: UUID?) throws -> UUID {
    if let categoryID, promptCategoryStore.categories.contains(where: { $0.id == categoryID }) {
      return categoryID
    }
    if categoryID != nil {
      throw PromptDomainError.invalidCategoryID
    }
    guard let rootID = promptCategoryStore.rootPromptCategory()?.id else {
      throw PromptDomainError.rootCategoryMissing
    }
    return rootID
  }

  private func validatePromptItems(_ promptItems: [PromptItem]) throws {
    let validIDs = Set(promptLibrary.items.map(\.id))
    guard promptItems.allSatisfy({ validIDs.contains($0.id) }) else {
      throw PromptDomainError.invalidPromptID
    }
  }

  private func saveAndReload() throws {
    do {
      try promptLibrary.context.save()
      promptCategoryStore.load()
      promptTagStore.load()
      promptLibrary.load()
    } catch {
      promptLibrary.context.rollback()
      promptCategoryStore.load()
      promptTagStore.load()
      promptLibrary.load()
      throw error
    }
  }
}
