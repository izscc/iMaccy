import Foundation
import SwiftData

@Model
final class PromptItem {
  var id: UUID
  var title: String
  var plainText: String
  var normalizedText: String
  var isFavorite: Bool
  var createdAt: Date
  var updatedAt: Date
  var usageCount: Int
  var sourceHistoryItemID: String?
  var categoryID: UUID?

  init(
    id: UUID = UUID(),
    title: String,
    plainText: String,
    normalizedText: String,
    isFavorite: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    usageCount: Int = 0,
    sourceHistoryItemID: String? = nil,
    categoryID: UUID? = nil
  ) {
    self.id = id
    self.title = title
    self.plainText = plainText
    self.normalizedText = normalizedText
    self.isFavorite = isFavorite
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.usageCount = usageCount
    self.sourceHistoryItemID = sourceHistoryItemID
    self.categoryID = categoryID
  }
}

@Model
final class PromptCategory {
  var id: UUID
  var name: String
  var parentID: UUID?
  var sortOrder: Int
  var isSystem: Bool
  var symbolName: String

  init(
    id: UUID = UUID(),
    name: String,
    parentID: UUID? = nil,
    sortOrder: Int = 0,
    isSystem: Bool = false,
    symbolName: String = "folder"
  ) {
    self.id = id
    self.name = name
    self.parentID = parentID
    self.sortOrder = sortOrder
    self.isSystem = isSystem
    self.symbolName = symbolName
  }
}

@Model
final class PromptTag {
  var id: UUID
  var name: String
  var colorHex: String?
  var createdAt: Date

  init(id: UUID = UUID(), name: String, colorHex: String? = nil, createdAt: Date = .now) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.createdAt = createdAt
  }
}

@Model
final class PromptItemTagLink {
  var id: UUID
  var promptItemID: UUID
  var promptTagID: UUID

  init(id: UUID = UUID(), promptItemID: UUID, promptTagID: UUID) {
    self.id = id
    self.promptItemID = promptItemID
    self.promptTagID = promptTagID
  }
}

extension String {
  var promptNormalizedText: String {
    components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .lowercased()
  }

  var promptDisplayTitle: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: "⏎")
      .replacingOccurrences(of: "\t", with: "⇥")
      .shortened(to: 120)
  }

  var promptTrimmedName: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var promptNormalizedName: String {
    promptTrimmedName
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .lowercased()
  }
}
