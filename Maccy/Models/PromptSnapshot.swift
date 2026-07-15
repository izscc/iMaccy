import Foundation

enum PromptSortOrder: String, CaseIterable, Identifiable {
  case recentlyUsed
  case usageFrequency
  case recentlyUpdated
  case title

  var id: Self { self }
}

enum PromptCategoryFilter: Equatable {
  case all
  case root
  case category(UUID)
}

struct PromptSnapshotResult {
  let items: [PromptItem]
  let unknownTagNames: [String]
  let hasUnterminatedQuote: Bool
}

/// An in-memory read model for Prompt browsing. It does not perform fetches or writes.
struct PromptSnapshot {
  let items: [PromptItem]
  let categories: [PromptCategory]
  let tags: [PromptTag]
  let links: [PromptItemTagLink]

  let categoryByID: [UUID: PromptCategory]
  let tagByID: [UUID: PromptTag]
  let tagIDsByPromptID: [UUID: Set<UUID>]
  let tagsByPromptID: [UUID: [PromptTag]]
  let categoryCounts: [UUID: Int]
  let tagCounts: [UUID: Int]

  init(
    items: [PromptItem],
    categories: [PromptCategory],
    tags: [PromptTag],
    links: [PromptItemTagLink]
  ) {
    self.items = items
    self.categories = categories
    self.tags = tags
    self.links = links

    let categoryByID = categories.reduce(into: [UUID: PromptCategory]()) { result, category in
      result[category.id] = category
    }
    let tagByID = tags.reduce(into: [UUID: PromptTag]()) { result, tag in
      result[tag.id] = tag
    }
    self.categoryByID = categoryByID
    self.tagByID = tagByID

    let promptIDs = Set(items.map(\.id))
    var tagIDsByPromptID = items.reduce(into: [UUID: Set<UUID>]()) { result, item in
      result[item.id] = []
    }
    var tagCounts: [UUID: Int] = [:]
    for link in links
    where promptIDs.contains(link.promptItemID) && tagByID[link.promptTagID] != nil {
      tagIDsByPromptID[link.promptItemID, default: []].insert(link.promptTagID)
    }
    for tagIDs in tagIDsByPromptID.values {
      for tagID in tagIDs {
        tagCounts[tagID, default: 0] += 1
      }
    }
    self.tagIDsByPromptID = tagIDsByPromptID
    self.tagCounts = tagCounts

    var tagsByPromptID = items.reduce(into: [UUID: [PromptTag]]()) { result, item in
      result[item.id] = []
    }
    for (promptID, tagIDs) in tagIDsByPromptID {
      tagsByPromptID[promptID] =
        tagIDs
        .compactMap { tagByID[$0] }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    self.tagsByPromptID = tagsByPromptID

    var categoryCounts: [UUID: Int] = [:]
    let rootID = categories.first(where: { $0.isSystem && $0.parentID == nil })?.id
    for item in items {
      if let categoryID = item.categoryID, categoryByID[categoryID] != nil {
        categoryCounts[categoryID, default: 0] += 1
      } else if let rootID {
        categoryCounts[rootID, default: 0] += 1
      }
    }
    self.categoryCounts = categoryCounts
  }

  var rootCategoryID: UUID? {
    categories.first(where: { $0.isSystem && $0.parentID == nil })?.id
  }

  func result(
    searchQuery: String = "",
    favoritesOnly: Bool = false,
    categoryFilter: PromptCategoryFilter = .all,
    selectedTagIDs: Set<UUID> = [],
    sortOrder: PromptSortOrder = .recentlyUpdated
  ) -> PromptSnapshotResult {
    let parsed = PromptSearchParser.parse(searchQuery)
    let normalizedTags = Dictionary(grouping: tags) { normalizeName($0.name) }
    var parsedTagIDs = Set<UUID>()
    var unknownTagNames: [String] = []
    var unknownTagKeys = Set<String>()
    for name in parsed.tagNames {
      let key = normalizeName(name)
      if let tag = normalizedTags[key]?.first {
        parsedTagIDs.insert(tag.id)
      } else if unknownTagKeys.insert(key).inserted {
        unknownTagNames.append(name)
      }
    }

    if parsed.hasUnterminatedQuote || !unknownTagNames.isEmpty {
      return PromptSnapshotResult(
        items: [],
        unknownTagNames: unknownTagNames,
        hasUnterminatedQuote: parsed.hasUnterminatedQuote
      )
    }

    let requiredTagIDs = selectedTagIDs.union(parsedTagIDs)
    let rootID = rootCategoryID
    let filtered = items.filter { item in
      guard !favoritesOnly || item.isFavorite else { return false }

      switch categoryFilter {
      case .all:
        break
      case .root:
        guard item.categoryID == nil || item.categoryID == rootID else { return false }
      case .category(let categoryID):
        guard item.categoryID == categoryID else { return false }
      }

      let itemTagIDs = tagIDsByPromptID[item.id, default: []]
      guard requiredTagIDs.isSubset(of: itemTagIDs) else { return false }

      guard !parsed.textQuery.isEmpty else { return true }
      return item.title.localizedCaseInsensitiveContains(parsed.textQuery)
        || item.plainText.localizedCaseInsensitiveContains(parsed.textQuery)
    }

    return PromptSnapshotResult(
      items: sort(filtered, by: sortOrder),
      unknownTagNames: unknownTagNames,
      hasUnterminatedQuote: parsed.hasUnterminatedQuote
    )
  }

  func visibleItems(
    searchQuery: String = "",
    favoritesOnly: Bool = false,
    categoryFilter: PromptCategoryFilter = .all,
    selectedTagIDs: Set<UUID> = [],
    sortOrder: PromptSortOrder = .recentlyUpdated
  ) -> [PromptItem] {
    result(
      searchQuery: searchQuery,
      favoritesOnly: favoritesOnly,
      categoryFilter: categoryFilter,
      selectedTagIDs: selectedTagIDs,
      sortOrder: sortOrder
    ).items
  }

  private func sort(_ items: [PromptItem], by order: PromptSortOrder) -> [PromptItem] {
    items.sorted { lhs, rhs in
      switch order {
      case .recentlyUsed:
        if lhs.lastUsedAt != rhs.lastUsedAt {
          return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
      case .recentlyUpdated:
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
      case .usageFrequency:
        if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
      case .title:
        let comparison = lhs.title.localizedCompare(rhs.title)
        if comparison != .orderedSame { return comparison == .orderedAscending }
      }

      if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private func normalizeName(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .lowercased()
  }
}
