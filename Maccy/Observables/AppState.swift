import AppKit
import Defaults
import Foundation
import Observation
import Settings
import SwiftData

struct PopupWindowSizePolicy {
  let historySize: NSSize
  let promptExpandedMinWidth: CGFloat

  func size(for scope: LibraryScope, totalContentHeight: CGFloat) -> NSSize {
    switch scope {
    case .history:
      return NSSize(width: historySize.width, height: min(totalContentHeight, historySize.height))
    case .prompt, .favorites:
      return NSSize(width: max(historySize.width, promptExpandedMinWidth), height: historySize.height)
    }
  }
}

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
  let promptExpandedMinWidth: CGFloat = 980

  var currentScope: LibraryScope = Defaults[.defaultLibraryScope] {
    didSet {
      guard oldValue != currentScope else { return }
      if oldValue == .history, let panelSize = appDelegate?.panel.frame.size {
        recordHistoryPresentedWindowSize(panelSize)
      }
      synchronizePromptFilterScope()
      if currentScope != .history {
        popup.pinnedItemsHeight = 0
        popup.footerHeight = 0
        syncPromptSelectionAfterVisibilityChange()
      } else {
        selectDefaultItemForCurrentScope()
      }
      popup.needsResize = true
    }
  }

  var selectedPromptItem: PromptItem? {
    didSet {
      guard oldValue?.id != selectedPromptItem?.id else { return }
      popup.needsResize = true
    }
  }

  var selectedPromptIDs: Set<UUID> = []
  var leadPromptSelectionID: UUID?
  var isPromptMultiSelecting: Bool {
    currentScope != .history && selectedPromptIDs.count >= 2
  }
  var selectedPromptItems: [PromptItem] {
    visiblePromptItems.filter { selectedPromptIDs.contains($0.id) }
  }
  var recentPromptBookmarks: [PromptCategory] {
    let limit = Defaults[.promptRecentBookmarkLimit]
    guard limit > 0 else { return [] }
    return promptCategoryStore.recentBookmarks(limit: limit)
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
      selectedCategoryID: promptFilter.selectedCategoryID,
      selectedTagIDs: promptFilter.selectedTagIDs,
      tagStore: promptTagStore
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
        syncPromptSelectionAfterVisibilityChange()
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
  @ObservationIgnored
  private var preservePromptSelectionDuringSelectionChange = false
  @ObservationIgnored
  private var historyPresentedWindowSize: NSSize?

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
    promptLibrary = PromptLibrary()
    promptCategoryStore = PromptCategoryStore()
    promptTagStore = PromptTagStore()
    promptFilter = PromptFilterStateStore()
    promptOrganizer = PromptOrganizer(
      promptLibrary: promptLibrary,
      promptCategoryStore: promptCategoryStore,
      promptTagStore: promptTagStore
    )
    synchronizePromptFilterScope()
  }

  func bootstrapPromptLibrary() {
    promptCategoryStore.seedDefaultsIfNeeded()
    promptCategoryStore.load()
    promptTagStore.load()
    promptLibrary.load()
    currentScope = Defaults[.defaultLibraryScope]
    popup.needsResize = true
  }

  func selectWithoutScrolling(_ item: UUID?) {
    history.selectedItem = nil
    footer.selectedItem = nil

    switch currentScope {
    case .history:
      selectedPromptItem = nil
      if let item, let historyItem = history.items.first(where: { $0.id == item }) {
        history.selectedItem = historyItem
      } else if let item, let footerItem = footer.items.first(where: { $0.id == item }) {
        footer.selectedItem = footerItem
      }
    case .prompt, .favorites:
      if let item, let promptItem = visiblePromptItems.first(where: { $0.id == item }) {
        selectedPromptItem = promptItem
        if !preservePromptSelectionDuringSelectionChange {
          selectedPromptIDs = [promptItem.id]
          leadPromptSelectionID = promptItem.id
        }
      } else if !preservePromptSelectionDuringSelectionChange {
        selectedPromptItem = nil
        selectedPromptIDs.removeAll()
        leadPromptSelectionID = nil
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

  func selectPromptListItem(_ item: PromptItem?) {
    guard let item else {
      selectedPromptIDs.removeAll()
      leadPromptSelectionID = nil
      selectedPromptItem = nil
      return
    }

    preservePromptSelectionDuringSelectionChange = false
    selection = item.id
  }

  func togglePromptMultiSelection(_ item: PromptItem) {
    guard currentScope != .history else { return }

    let alreadySelected = selectedPromptIDs.contains(item.id)

    preservePromptSelectionDuringSelectionChange = true
    selection = item.id
    preservePromptSelectionDuringSelectionChange = false

    if alreadySelected {
      selectedPromptIDs.remove(item.id)
      if selectedPromptIDs.isEmpty {
        leadPromptSelectionID = nil
        selectedPromptItem = nil
        selection = nil
      } else if leadPromptSelectionID == item.id {
        let replacement = visiblePromptItems.first(where: { selectedPromptIDs.contains($0.id) })
        leadPromptSelectionID = replacement?.id
        selectedPromptItem = replacement
        if let replacement {
          preservePromptSelectionDuringSelectionChange = true
          selection = replacement.id
          preservePromptSelectionDuringSelectionChange = false
        }
      }
    } else {
      selectedPromptIDs.insert(item.id)
      leadPromptSelectionID = item.id
      selectedPromptItem = item
    }

    popup.needsResize = true
  }

  func isPromptItemSelected(_ item: PromptItem) -> Bool {
    selectedPromptIDs.contains(item.id)
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

  func archiveHistoryItemToPrompt(_ item: HistoryItem, categoryID: UUID? = nil) {
    guard let promptItem = promptOrganizer.moveToPrompt(item, targetCategoryID: categoryID) else {
      return
    }

    refreshPromptData(selectPromptID: promptItem.id)
    currentScope = .prompt
    selection = promptItem.id
  }

  func createPromptBookmark(name: String) throws -> PromptCategory {
    let category = try promptCategoryStore.createBookmark(name)
    refreshPromptData()
    return category
  }

  func renamePromptBookmark(_ category: PromptCategory, name: String) throws {
    try promptCategoryStore.renameBookmark(category, to: name)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
  }

  func deletePromptBookmark(_ category: PromptCategory) throws {
    if promptFilter.selectedCategoryID == category.id {
      promptFilter.selectedCategoryID = nil
    }
    try promptCategoryStore.deleteBookmark(category)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
  }

  func createPromptTag(name: String) throws -> PromptTag {
    let tag = try promptTagStore.createTag(name)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
    return tag
  }

  func findOrCreatePromptTag(name: String) throws -> PromptTag {
    let tag = try promptTagStore.findOrCreateTag(name)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
    return tag
  }

  func renamePromptTag(_ tag: PromptTag, name: String) throws {
    try promptTagStore.renameTag(tag, to: name)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
  }

  func deletePromptTag(_ tag: PromptTag) {
    promptFilter.selectedTagIDs.remove(tag.id)
    promptTagStore.deleteTag(tag)
    refreshPromptData(selectPromptID: selectedPromptItem?.id)
  }

  func assignPromptToCategory(_ item: PromptItem?, categoryID: UUID?) {
    guard let item else { return }
    promptOrganizer.assignPrompt(item, to: categoryID)
    refreshPromptData(selectPromptID: item.id)
  }

  func setPromptTagIDs(_ item: PromptItem?, tagIDs: Set<UUID>) {
    guard let item else { return }
    promptOrganizer.setTagIDs(tagIDs, for: item)
    refreshPromptData(selectPromptID: item.id)
  }

  func removePromptTag(_ tag: PromptTag, from item: PromptItem?) {
    guard let item else { return }
    promptOrganizer.removeTag(tag, from: item)
    refreshPromptData(selectPromptID: item.id)
  }

  func bulkAssignPromptsToCategory(_ categoryID: UUID?) {
    guard !selectedPromptItems.isEmpty else { return }
    let leadID = leadPromptSelectionID
    promptOrganizer.assignPrompts(selectedPromptItems, to: categoryID)
    refreshPromptData(selectPromptID: leadID)
  }

  func bulkAddPromptTagIDs(_ tagIDs: Set<UUID>) {
    guard !selectedPromptItems.isEmpty, !tagIDs.isEmpty else { return }
    let leadID = leadPromptSelectionID
    promptOrganizer.addTags(tagIDs, to: selectedPromptItems)
    refreshPromptData(selectPromptID: leadID)
  }

  func bulkRemovePromptTagIDs(_ tagIDs: Set<UUID>) {
    guard !selectedPromptItems.isEmpty, !tagIDs.isEmpty else { return }
    let leadID = leadPromptSelectionID
    promptOrganizer.removeTags(tagIDs, from: selectedPromptItems)
    refreshPromptData(selectPromptID: leadID)
  }

  func bulkSetFavoriteForSelectedPrompts(_ value: Bool) {
    guard !selectedPromptItems.isEmpty else { return }
    let leadID = leadPromptSelectionID
    promptOrganizer.setFavorite(value, for: selectedPromptItems)
    refreshPromptData(selectPromptID: leadID)
  }

  func bulkDeleteSelectedPrompts() {
    guard !selectedPromptItems.isEmpty else { return }
    promptOrganizer.deletePrompts(selectedPromptItems)
    selectedPromptIDs.removeAll()
    leadPromptSelectionID = nil
    syncPromptSelectionAfterVisibilityChange()
    popup.needsResize = true
  }

  func promptTags(for item: PromptItem?) -> [PromptTag] {
    guard let item else { return [] }
    return promptTagStore.tags(for: item.id)
  }

  func promptTagSummary(for item: PromptItem?) -> [PromptTag] {
    guard Defaults[.showPromptTagSummary] else { return [] }
    return promptTags(for: item)
  }

  func promptCategoryBadgeName(for item: PromptItem?) -> String? {
    guard Defaults[.showPromptCategoryBadge] else {
      return nil
    }
    guard let item,
          let categoryID = item.categoryID,
          !promptCategoryStore.isRootCategoryID(categoryID) else {
      return nil
    }
    return promptCategoryStore.categoryName(for: categoryID)
  }

  func promptCategoryName(for item: PromptItem?) -> String {
    guard let item else { return "Prompt 根目录" }
    return promptCategoryStore.categoryName(for: item.categoryID)
  }

  func setPromptCategoryFilter(_ categoryID: UUID?) {
    promptFilter.selectedCategoryID = categoryID
    syncPromptSelectionAfterVisibilityChange()
    popup.needsResize = true
  }

  func togglePromptTagFilter(_ tagID: UUID) {
    if promptFilter.selectedTagIDs.contains(tagID) {
      promptFilter.selectedTagIDs.remove(tagID)
    } else {
      promptFilter.selectedTagIDs.insert(tagID)
    }
    syncPromptSelectionAfterVisibilityChange()
    popup.needsResize = true
  }

  private func refreshPromptData(selectPromptID: UUID? = nil) {
    promptCategoryStore.seedDefaultsIfNeeded()
    promptCategoryStore.load()
    promptTagStore.load()
    promptLibrary.load()

    if currentScope != .history {
      if let selectPromptID, visiblePromptItems.contains(where: { $0.id == selectPromptID }) {
        preservePromptSelectionDuringSelectionChange = false
        selection = selectPromptID
      } else {
        syncPromptSelectionAfterVisibilityChange()
      }
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
            identifier: Settings.PaneIdentifier.prompt,
            title: "Prompt",
            toolbarIcon: NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil) ?? NSImage.gearshape!
          ) {
            PromptSettingsPane()
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

  func recordHistoryPresentedWindowSize(_ size: NSSize) {
    historyPresentedWindowSize = size
  }

  var historyReferenceWindowSize: NSSize {
    let size = historyPresentedWindowSize ?? Defaults[.windowSize]
    return NSSize(width: max(size.width, 320), height: max(size.height, 240))
  }

  func targetWindowSize(forTotalHeight totalHeight: CGFloat) -> NSSize {
    PopupWindowSizePolicy(
      historySize: historyReferenceWindowSize,
      promptExpandedMinWidth: promptExpandedMinWidth
    )
    .size(for: currentScope, totalContentHeight: totalHeight)
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
      syncPromptSelectionAfterVisibilityChange()
    }
  }

  private func syncPromptSelectionAfterVisibilityChange() {
    guard currentScope != .history else { return }

    let visibleIDs = Set(visiblePromptItems.map(\.id))
    if !selectedPromptIDs.isEmpty {
      let kept = selectedPromptIDs.intersection(visibleIDs)
      if !kept.isEmpty {
        selectedPromptIDs = kept
        let newLead = leadPromptSelectionID.flatMap { kept.contains($0) ? $0 : nil } ??
          visiblePromptItems.first(where: { kept.contains($0.id) })?.id
        leadPromptSelectionID = newLead
        selectedPromptItem = visiblePromptItems.first(where: { $0.id == newLead })
        preservePromptSelectionDuringSelectionChange = true
        selection = newLead
        preservePromptSelectionDuringSelectionChange = false
        return
      }
    }

    selectedPromptIDs.removeAll()
    leadPromptSelectionID = nil
    if let first = visiblePromptItems.first {
      preservePromptSelectionDuringSelectionChange = false
      selection = first.id
    } else {
      selectedPromptItem = nil
      selection = nil
    }
  }
}
