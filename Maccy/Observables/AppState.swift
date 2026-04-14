import AppKit
import Defaults
import Foundation
import Observation
import Settings
import SwiftData

@MainActor
@Observable
class AppState: Sendable {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer

  let promptLibrary: PromptLibrary
  let promptCategoryStore: PromptCategoryStore
  let promptTagStore: PromptTagStore
  let promptFilter: PromptFilterStateStore
  let promptOrganizer: PromptOrganizer

  var currentScope: LibraryScope = .history {
    didSet {
      guard oldValue != currentScope else { return }
      synchronizePromptFilterScope()
      if currentScope != .history {
        popup.pinnedItemsHeight = 0
        popup.footerHeight = 0
        ensurePromptWindowWidth()
      }
      selectDefaultItemForCurrentScope()
      popup.needsResize = true
    }
  }

  var selectedPromptItem: PromptItem? {
    didSet {
      guard oldValue?.id != selectedPromptItem?.id else { return }
      popup.needsResize = true
    }
  }

  var scrollTarget: UUID?
  var selection: UUID? {
    didSet {
      selectWithoutScrolling(selection)
      scrollTarget = selection
    }
  }

  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        selection = hoverSelection
      }
    }
  }

  var visiblePromptItems: [PromptItem] {
    promptLibrary.visibleItems(
      searchQuery: promptFilter.searchQuery,
      favoritesOnly: promptFilter.favoritesOnly,
      selectedCategoryID: promptFilter.selectedCategoryID
    )
  }

  var activeSearchQuery: String {
    get {
      switch currentScope {
      case .history:
        return history.searchQuery
      case .prompt, .favorites:
        return promptFilter.searchQuery
      }
    }
    set {
      switch currentScope {
      case .history:
        history.searchQuery = newValue
      case .prompt, .favorites:
        promptFilter.searchQuery = newValue
        if newValue.isEmpty {
          selectDefaultItemForCurrentScope()
        } else {
          highlightFirst()
        }
        popup.needsResize = true
      }
    }
  }

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !activeSearchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
    promptLibrary = PromptLibrary()
    promptCategoryStore = PromptCategoryStore()
    promptTagStore = PromptTagStore()
    promptFilter = PromptFilterStateStore()
    promptOrganizer = PromptOrganizer(promptLibrary: promptLibrary, promptCategoryStore: promptCategoryStore)
    synchronizePromptFilterScope()
  }

  func bootstrapPromptLibrary() {
    promptCategoryStore.seedDefaultsIfNeeded()
    promptCategoryStore.load()
    promptTagStore.load()
    promptLibrary.load()
    popup.needsResize = true
  }

  func selectWithoutScrolling(_ item: UUID?) {
    history.selectedItem = nil
    footer.selectedItem = nil
    selectedPromptItem = nil

    switch currentScope {
    case .history:
      if let item, let historyItem = history.items.first(where: { $0.id == item }) {
        history.selectedItem = historyItem
      } else if let item, let footerItem = footer.items.first(where: { $0.id == item }) {
        footer.selectedItem = footerItem
      }
    case .prompt, .favorites:
      if let item, let promptItem = visiblePromptItems.first(where: { $0.id == item }) {
        selectedPromptItem = promptItem
      }
    }
  }

  func select() {
    switch currentScope {
    case .history:
      if let item = history.selectedItem, history.items.contains(item) {
        history.select(item)
      } else if let item = footer.selectedItem {
        if item.confirmation != nil {
          item.showConfirmation = true
        } else {
          item.action()
        }
      } else {
        Clipboard.shared.copy(history.searchQuery)
        history.searchQuery = ""
      }
    case .prompt, .favorites:
      if let item = selectedPromptItem, visiblePromptItems.contains(where: { $0.id == item.id }) {
        selectPrompt(item)
      } else if !activeSearchQuery.isEmpty {
        Clipboard.shared.copy(activeSearchQuery)
        activeSearchQuery = ""
      }
    }
  }

  func selectPrompt(_ item: PromptItem?) {
    guard let item else { return }

    promptLibrary.markUsed(item)
    Clipboard.shared.copy(item.plainText)
    if Defaults[.pasteByDefault] {
      Clipboard.shared.paste()
    }
    popup.close()
    activeSearchQuery = ""
  }

  func deleteSelectedPrompt() {
    deletePrompt(selectedPromptItem)
  }

  func deletePrompt(_ item: PromptItem?) {
    guard let item else { return }

    let fallbackSelection = visiblePromptItems
      .filter { $0.id != item.id }
      .first?.id

    promptLibrary.delete(item)
    refreshPromptData(selectPromptID: fallbackSelection)
  }

  func toggleFavoritePrompt(_ item: PromptItem?) {
    guard let item else { return }

    let toggledItemID = item.id
    let willRemainVisible = !(currentScope == .favorites && item.isFavorite)

    promptLibrary.toggleFavorite(item)
    refreshPromptData(selectPromptID: willRemainVisible ? toggledItemID : visiblePromptItems.first?.id)
  }

  func archiveHistoryItemToPrompt(_ item: HistoryItem) {
    guard let promptItem = promptOrganizer.moveToPrompt(item) else {
      return
    }

    refreshPromptData(selectPromptID: promptItem.id)
    currentScope = .prompt
    selection = promptItem.id
  }

  private func refreshPromptData(selectPromptID: UUID? = nil) {
    promptCategoryStore.seedDefaultsIfNeeded()
    promptCategoryStore.load()
    promptTagStore.load()
    promptLibrary.load()

    if currentScope != .history {
      let targetID = selectPromptID.flatMap { id in
        visiblePromptItems.contains(where: { $0.id == id }) ? id : nil
      } ?? visiblePromptItems.first?.id
      selection = targetID
    }
    popup.needsResize = true
  }

  private func selectFromKeyboardNavigation(_ id: UUID?) {
    isKeyboardNavigating = true
    selection = id
  }

  func highlightFirst() {
    switch currentScope {
    case .history:
      if let item = history.items.first(where: \.isVisible) {
        selectFromKeyboardNavigation(item.id)
      }
    case .prompt, .favorites:
      selectFromKeyboardNavigation(visiblePromptItems.first?.id)
    }
  }

  func highlightPrevious() {
    switch currentScope {
    case .history:
      isKeyboardNavigating = true
      if let selectedItem = history.selectedItem {
        if let nextItem = history.items.filter(\.isVisible).item(before: selectedItem) {
          selectFromKeyboardNavigation(nextItem.id)
        }
      } else if let selectedItem = footer.selectedItem {
        if let nextItem = footer.items.filter(\.isVisible).item(before: selectedItem) {
          selectFromKeyboardNavigation(nextItem.id)
        } else if selectedItem == footer.items.first(where: \.isVisible),
                  let nextItem = history.items.last(where: \.isVisible) {
          selectFromKeyboardNavigation(nextItem.id)
        }
      }
    case .prompt, .favorites:
      guard let selectedPromptItem else {
        selectFromKeyboardNavigation(visiblePromptItems.last?.id)
        return
      }
      if let index = visiblePromptItems.firstIndex(where: { $0.id == selectedPromptItem.id }), index > 0 {
        selectFromKeyboardNavigation(visiblePromptItems[index - 1].id)
      }
    }
  }

  func highlightNext() {
    switch currentScope {
    case .history:
      if let selectedItem = history.selectedItem {
        if let nextItem = history.items.filter(\.isVisible).item(after: selectedItem) {
          selectFromKeyboardNavigation(nextItem.id)
        } else if selectedItem == history.items.filter(\.isVisible).last,
                  let nextItem = footer.items.first(where: \.isVisible) {
          selectFromKeyboardNavigation(nextItem.id)
        }
      } else if let selectedItem = footer.selectedItem {
        if let nextItem = footer.items.filter(\.isVisible).item(after: selectedItem) {
          selectFromKeyboardNavigation(nextItem.id)
        }
      } else {
        selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
      }
    case .prompt, .favorites:
      guard let selectedPromptItem else {
        selectFromKeyboardNavigation(visiblePromptItems.first?.id)
        return
      }
      if let index = visiblePromptItems.firstIndex(where: { $0.id == selectedPromptItem.id }),
         visiblePromptItems.indices.contains(index + 1) {
        selectFromKeyboardNavigation(visiblePromptItems[index + 1].id)
      }
    }
  }

  func highlightLast() {
    switch currentScope {
    case .history:
      if let selectedItem = history.selectedItem {
        if selectedItem == history.items.filter(\.isVisible).last,
           let nextItem = footer.items.first(where: \.isVisible) {
          selectFromKeyboardNavigation(nextItem.id)
        } else {
          selectFromKeyboardNavigation(history.items.last(where: \.isVisible)?.id)
        }
      } else if footer.selectedItem != nil {
        selectFromKeyboardNavigation(footer.items.last(where: \.isVisible)?.id)
      } else {
        selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
      }
    case .prompt, .favorites:
      selectFromKeyboardNavigation(visiblePromptItems.last?.id)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle!
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }

  private func synchronizePromptFilterScope() {
    switch currentScope {
    case .history:
      promptFilter.scope = .prompt
      promptFilter.favoritesOnly = false
    case .prompt:
      promptFilter.scope = .prompt
      promptFilter.favoritesOnly = false
    case .favorites:
      promptFilter.scope = .favorites
      promptFilter.favoritesOnly = true
    }
  }

  private func selectDefaultItemForCurrentScope() {
    switch currentScope {
    case .history:
      selection = history.unpinnedItems.first?.id ?? history.pinnedItems.first?.id
    case .prompt, .favorites:
      selection = visiblePromptItems.first?.id
    }
  }

  private func ensurePromptWindowWidth(minWidth: CGFloat = 720) {
    guard currentScope != .history,
          let panel = appDelegate?.panel,
          panel.frame.width < minWidth else {
      return
    }

    var frame = panel.frame
    frame.origin.x -= (minWidth - frame.width) / 2
    frame.size.width = minWidth
    panel.setFrame(frame, display: true, animate: true)
    panel.saveWindowFrame(frame: frame)
  }
}

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

@MainActor
@Observable
class PromptFilterStateStore {
  var scope: PromptScope = .prompt
  var searchQuery: String = ""
  var selectedCategoryID: UUID?
  var favoritesOnly: Bool = false
}

@MainActor
@Observable
class PromptCategoryStore {
  var categories: [PromptCategory] = []

  func load() {
    let descriptor = FetchDescriptor<PromptCategory>()
    categories = (try? Storage.shared.context.fetch(descriptor))?.sorted {
      if $0.isSystem != $1.isSystem {
        return $0.isSystem && !$1.isSystem
      }
      if $0.sortOrder != $1.sortOrder {
        return $0.sortOrder < $1.sortOrder
      }
      return $0.name < $1.name
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

  func categoryName(for id: UUID?) -> String {
    guard let id else { return "Prompt" }
    return categories.first(where: { $0.id == id })?.name ?? "Prompt"
  }
}

@MainActor
@Observable
class PromptTagStore {
  var tags: [PromptTag] = []

  func load() {
    let descriptor = FetchDescriptor<PromptTag>()
    tags = (try? Storage.shared.context.fetch(descriptor))?.sorted {
      $0.name.localizedCompare($1.name) == .orderedAscending
    } ?? []
  }
}

@MainActor
@Observable
class PromptLibrary {
  var items: [PromptItem] = []

  func load() {
    let descriptor = FetchDescriptor<PromptItem>()
    items = sorted((try? Storage.shared.context.fetch(descriptor)) ?? [])
  }

  func visibleItems(searchQuery: String, favoritesOnly: Bool, selectedCategoryID: UUID?) -> [PromptItem] {
    let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    return items.filter { item in
      if favoritesOnly && !item.isFavorite {
        return false
      }

      if let selectedCategoryID, item.categoryID != selectedCategoryID {
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

  init(promptLibrary: PromptLibrary, promptCategoryStore: PromptCategoryStore) {
    self.promptLibrary = promptLibrary
    self.promptCategoryStore = promptCategoryStore
  }

  func canArchive(_ historyItem: HistoryItem) -> Bool {
    historyItem.promptPlainText != nil
  }

  func moveToPrompt(_ historyItem: HistoryItem) -> PromptItem? {
    guard let plainText = historyItem.promptPlainText,
          let rootCategory = promptCategoryStore.rootPromptCategory() else {
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
        existingPrompt.categoryID = rootCategory.id
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
      categoryID: rootCategory.id
    )
    Storage.shared.context.insert(promptItem)
    try? Storage.shared.context.save()
    promptLibrary.load()
    return promptItem
  }
}

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

private extension String {
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
}
