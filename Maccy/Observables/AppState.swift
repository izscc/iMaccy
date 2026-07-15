import AppKit
import Defaults
import Foundation
import Observation
import Settings
import SwiftData

struct PopupWindowSizePolicy {
  let historySize: NSSize
  let promptExpandedMinWidth: CGFloat
  let promptMinimumHeight: CGFloat

  func size(for scope: LibraryScope, totalContentHeight: CGFloat) -> NSSize {
    switch scope {
    case .history:
      return historySize
    case .prompt, .favorites:
      return NSSize(
        width: max(historySize.width, promptExpandedMinWidth),
        height: max(historySize.height, promptMinimumHeight)
      )
    }
  }
}

@MainActor
@Observable
class AppState: Sendable { // swiftlint:disable:this type_body_length
  static let shared = AppState()

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  let itemActionCoordinator: ItemActionCoordinator

  let promptLibrary: PromptLibrary
  let promptCategoryStore: PromptCategoryStore
  let promptTagStore: PromptTagStore
  let promptFilter: PromptFilterStateStore
  let promptOrganizer: PromptOrganizer
  let promptExpandedMinWidth: CGFloat = 760
  let promptMinimumHeight: CGFloat = 320
  var isPromptLibraryLoaded = false
  var isPromptMetadataLoaded = false
  var isPromptLoading = false
  var promptErrorMessage: String?
  var unknownPromptTagNames: [String] = []
  var promptSearchHasUnterminatedQuote = false
  var promptListRevision = 0
  var showPromptBulkDeleteConfirmation = false

  @ObservationIgnored
  private var promptSnapshot: PromptSnapshot?
  private var cachedVisiblePromptItems: [PromptItem] = []
  @ObservationIgnored
  private var promptSearchTask: Task<Void, Never>?
  @ObservationIgnored
  private let fallbackPromptUndoManager = UndoManager()

  var currentScope: LibraryScope = Defaults[.defaultLibraryScope] {
    didSet {
      guard oldValue != currentScope else { return }
      if oldValue == .history, let panelSize = appDelegate?.panel.frame.size {
        recordHistoryPresentedWindowSize(panelSize)
      }
      synchronizePromptFilterScope()
      if currentScope != .history {
        ensurePromptLibraryLoaded()
        popup.pinnedItemsHeight = 0
        popup.footerHeight = 0
        if isPromptLibraryLoaded {
          updatePromptVisibility()
        }
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
  var promptSelectionAnchorID: UUID?
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

  var visiblePromptItems: [PromptItem] { cachedVisiblePromptItems }

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
        schedulePromptVisibilityUpdate()
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
  private var lastPromptLoadErrorMessage: String?
  @ObservationIgnored
  private var historyPresentedWindowSize: NSSize?

  init() {
    history = History.shared
    footer = Footer()
    let popup = Popup()
    self.popup = popup
    itemActionCoordinator = ItemActionCoordinator(
      closePanel: { popup.close() },
      restoreFocus: { await popup.restoreFocusForPasting() },
      paste: { Clipboard.shared.paste() }
    )
    let promptContext = Storage.shared.context
    promptLibrary = PromptLibrary(context: promptContext)
    promptCategoryStore = PromptCategoryStore(context: promptContext)
    promptTagStore = PromptTagStore(context: promptContext)
    promptFilter = PromptFilterStateStore()
    promptOrganizer = PromptOrganizer(
      promptLibrary: promptLibrary,
      promptCategoryStore: promptCategoryStore,
      promptTagStore: promptTagStore
    )
    synchronizePromptFilterScope()
  }

  func bootstrapPromptLibrary() {
    guard !isPromptLibraryLoaded else { return }
    isPromptLoading = true
    defer { isPromptLoading = false }
    Diagnostics.measure(Diagnostics.Name.promptLoad) {
      promptCategoryStore.seedDefaultsIfNeeded()
      if promptCategoryStore.loadErrorMessage != nil {
        capturePromptLoadError()
        return
      }
      guard let rootID = promptCategoryStore.rootPromptCategory()?.id else {
        promptErrorMessage = PromptDomainError.rootCategoryMissing.localizedDescription
        return
      }
      isPromptMetadataLoaded = true
      do {
        _ = try PromptIntegrityRepair.run(context: promptLibrary.context, rootCategoryID: rootID)
      } catch {
        promptErrorMessage = error.localizedDescription
      }
      promptTagStore.load()
      promptLibrary.load()
      capturePromptLoadError()
      rebuildPromptSnapshot()
      isPromptLibraryLoaded = true
      popup.needsResize = true
    }
  }

  func bootstrapPromptMetadata() {
    guard !isPromptMetadataLoaded else { return }
    promptCategoryStore.seedDefaultsIfNeeded()
    capturePromptLoadError()
    guard promptCategoryStore.loadErrorMessage == nil else { return }
    isPromptMetadataLoaded = promptCategoryStore.rootPromptCategory() != nil
    if !isPromptMetadataLoaded {
      promptErrorMessage = PromptDomainError.rootCategoryMissing.localizedDescription
    }
  }

  func ensurePromptLibraryLoaded() {
    guard !isPromptLibraryLoaded, !isPromptLoading else { return }
    isPromptLoading = true
    Task { @MainActor in
      await Task.yield()
      bootstrapPromptLibrary()
    }
  }

  func clearPromptError() {
    promptErrorMessage = nil
    lastPromptLoadErrorMessage = nil
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
          promptSelectionAnchorID = promptItem.id
        }
      } else if !preservePromptSelectionDuringSelectionChange {
        selectedPromptItem = nil
        selectedPromptIDs.removeAll()
        leadPromptSelectionID = nil
        promptSelectionAnchorID = nil
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
      flushPromptSearch()
      if let item = selectedPromptItem, visiblePromptItems.contains(where: { $0.id == item.id }) {
        selectPrompt(item)
      } else if !activeSearchQuery.isEmpty {
        Clipboard.shared.copy(activeSearchQuery)
        activeSearchQuery = ""
      }
    }
  }

  func selectPrompt(_ item: PromptItem?) {
    performPromptAction(
      item,
      action: Defaults[.pasteByDefault] ? .paste : .copy,
      source: .keyboard
    )
  }

  func selectPromptFromPointer(_ item: PromptItem?) {
    performPromptAction(
      item,
      action: Defaults[.pasteByDefault] ? .paste : .copy,
      source: .pointer
    )
  }

  func copyPrompt(_ item: PromptItem?) {
    performPromptAction(item, action: .copy, source: .detailButton)
  }

  func pastePrompt(_ item: PromptItem?) {
    performPromptAction(item, action: .paste, source: .detailButton)
  }

  private func performPromptAction(_ item: PromptItem?, action: ItemAction, source: ActivationSource) {
    guard let item else { return }

    do {
      try promptLibrary.markUsed(item)
      rebuildPromptSnapshot()
    } catch {
      promptErrorMessage = error.localizedDescription
      return
    }

    if action != .copy {
      _ = Accessibility.check()
    }
    itemActionCoordinator.perform(action, source: source) {
      Clipboard.shared.copy(item.plainText)
    }

    if source != .detailButton {
      activeSearchQuery = ""
    }
  }

  func selectPromptListItem(_ item: PromptItem?) {
    guard let item else {
      selectedPromptIDs.removeAll()
      leadPromptSelectionID = nil
      promptSelectionAnchorID = nil
      selectedPromptItem = nil
      return
    }

    preservePromptSelectionDuringSelectionChange = false
    selection = item.id
    promptSelectionAnchorID = item.id
  }

  func extendPromptSelection(to item: PromptItem) {
    applyPromptSelectionState(
      PromptSelectionReducer.range(
        to: item.id,
        state: currentPromptSelectionState,
        visibleIDs: visiblePromptItems.map(\.id)
      )
    )
  }

  func selectAllVisiblePrompts() {
    guard currentScope != .history, !visiblePromptItems.isEmpty else { return }
    applyPromptSelectionState(
      PromptSelectionReducer.selectAll(
        visiblePromptItems.map(\.id),
        preferredLeadID: selectedPromptItem?.id
      )
    )
  }

  func clearPromptSelection() {
    applyPromptSelectionState(PromptSelectionState())
  }

  func extendPromptSelection(by offset: Int) {
    guard currentScope != .history, !visiblePromptItems.isEmpty else { return }
    let currentID = leadPromptSelectionID ?? selectedPromptItem?.id ?? visiblePromptItems.first?.id
    guard let currentID,
          let currentIndex = visiblePromptItems.firstIndex(where: { $0.id == currentID }) else { return }
    let targetIndex = min(max(currentIndex + offset, 0), visiblePromptItems.count - 1)
    extendPromptSelection(to: visiblePromptItems[targetIndex])
  }

  func togglePromptMultiSelection(_ item: PromptItem) {
    guard currentScope != .history else { return }
    applyPromptSelectionState(
      PromptSelectionReducer.toggle(
        item.id,
        state: currentPromptSelectionState,
        visibleIDs: visiblePromptItems.map(\.id)
      )
    )
  }

  func isPromptItemSelected(_ item: PromptItem) -> Bool {
    selectedPromptIDs.contains(item.id)
  }

  func deleteSelectedPrompt() {
    if selectedPromptIDs.count > 1 {
      requestBulkDeleteSelectedPrompts()
    } else {
      deletePrompt(selectedPromptItem)
    }
  }

  func requestBulkDeleteSelectedPrompts() {
    guard !selectedPromptItems.isEmpty else { return }
    if Defaults[.confirmPromptBulkDelete] {
      showPromptBulkDeleteConfirmation = true
    } else {
      bulkDeleteSelectedPrompts()
    }
  }

  func undoPromptAction() {
    promptUndoManager?.undo()
  }

  func redoPromptAction() {
    promptUndoManager?.redo()
  }

  func deletePrompt(_ item: PromptItem?) {
    guard let item else { return }
    let deletedRecord = DeletedPromptRecord(
      item: item,
      tagIDs: promptSnapshot?.tagIDsByPromptID[item.id] ?? []
    )

    let fallbackSelection = visiblePromptItems
      .filter { $0.id != item.id }
      .first?.id

    do {
      try promptOrganizer.deletePrompts([item])
      rebuildPromptSnapshot(selectPromptID: fallbackSelection)
      registerPromptUndo(actionName: NSLocalizedString("Delete Prompt", comment: "Undo action")) {
        $0.restoreDeletedPrompts([deletedRecord])
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func toggleFavoritePrompt(_ item: PromptItem?) {
    guard let item else { return }
    let previousValue = item.isFavorite

    let toggledItemID = item.id
    let willRemainVisible = !(currentScope == .favorites && item.isFavorite)

    do {
      try promptLibrary.toggleFavorite(item)
      promptCategoryStore.load()
      promptTagStore.load()
      rebuildPromptSnapshot(selectPromptID: willRemainVisible ? toggledItemID : visiblePromptItems.first?.id)
      registerPromptUndo(actionName: NSLocalizedString("Favorite Prompt", comment: "Undo action")) {
        $0.restorePromptFavorites([item.id: previousValue])
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func archiveHistoryItemToPrompt(_ item: HistoryItem, categoryID: UUID? = nil) {
    if !isPromptLibraryLoaded {
      bootstrapPromptLibrary()
    }
    guard isPromptLibraryLoaded else { return }
    do {
      guard let promptItem = try promptOrganizer.moveToPrompt(item, targetCategoryID: categoryID) else {
        return
      }
      rebuildPromptSnapshot(selectPromptID: promptItem.id)
      currentScope = .prompt
      selection = promptItem.id
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func createPrompt(title: String, plainText: String) throws -> PromptItem {
    let item = try promptLibrary.create(
      title: title,
      plainText: plainText,
      categoryID: defaultPromptCategoryID
    )
    promptCategoryStore.load()
    promptTagStore.load()
    rebuildPromptSnapshot(selectPromptID: item.id)
    return item
  }

  func updatePrompt(_ item: PromptItem, title: String, plainText: String) throws {
    try promptLibrary.update(item, title: title, plainText: plainText)
    promptCategoryStore.load()
    promptTagStore.load()
    rebuildPromptSnapshot(selectPromptID: item.id)
  }

  @discardableResult
  func duplicatePrompt(_ item: PromptItem) throws -> PromptItem {
    let copy = try promptOrganizer.duplicatePrompt(item)
    rebuildPromptSnapshot(selectPromptID: copy.id)
    return copy
  }

  func createPromptBookmark(name: String) throws -> PromptCategory {
    let category = try promptCategoryStore.createBookmark(name)
    rebuildPromptSnapshot()
    return category
  }

  func renamePromptBookmark(_ category: PromptCategory, name: String) throws {
    try promptCategoryStore.renameBookmark(category, to: name)
    rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
  }

  func deletePromptBookmark(_ category: PromptCategory) throws {
    if promptFilter.categoryFilter == .category(category.id) {
      promptFilter.categoryFilter = .all
    }
    try promptCategoryStore.deleteBookmark(category)
    promptLibrary.load()
    rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
  }

  func createPromptTag(name: String) throws -> PromptTag {
    let tag = try promptTagStore.createTag(name)
    rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
    return tag
  }

  func findOrCreatePromptTag(name: String) throws -> PromptTag {
    let tag = try promptTagStore.findOrCreateTag(name)
    rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
    return tag
  }

  func renamePromptTag(_ tag: PromptTag, name: String) throws {
    try promptTagStore.renameTag(tag, to: name)
    rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
  }

  func deletePromptTag(_ tag: PromptTag) {
    promptFilter.selectedTagIDs.remove(tag.id)
    do {
      try promptTagStore.deleteTag(tag)
      rebuildPromptSnapshot(selectPromptID: selectedPromptItem?.id)
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func assignPromptToCategory(_ item: PromptItem?, categoryID: UUID?) {
    guard let item else { return }
    let previousCategory = item.categoryID
    do {
      try promptOrganizer.assignPrompt(item, to: categoryID)
      rebuildPromptSnapshot(selectPromptID: item.id)
      registerPromptUndo(actionName: NSLocalizedString("Move Prompt", comment: "Undo action")) {
        $0.restorePromptCategories([item.id: previousCategory])
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func setPromptTagIDs(_ item: PromptItem?, tagIDs: Set<UUID>) {
    guard let item else { return }
    let previousTagIDs = promptSnapshot?.tagIDsByPromptID[item.id] ?? []
    do {
      try promptOrganizer.setTagIDs(tagIDs, for: item)
      rebuildPromptSnapshot(selectPromptID: item.id)
      registerPromptUndo(actionName: NSLocalizedString("Edit Prompt Tags", comment: "Undo action")) {
        $0.restorePromptTags([item.id: previousTagIDs])
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func removePromptTag(_ tag: PromptTag, from item: PromptItem?) {
    guard let item else { return }
    do {
      try promptOrganizer.removeTag(tag, from: item)
      rebuildPromptSnapshot(selectPromptID: item.id)
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func bulkAssignPromptsToCategory(_ categoryID: UUID?) {
    guard !selectedPromptItems.isEmpty else { return }
    let leadID = leadPromptSelectionID
    let previousCategories = Dictionary(uniqueKeysWithValues: selectedPromptItems.map { ($0.id, $0.categoryID) })
    do {
      try promptOrganizer.assignPrompts(selectedPromptItems, to: categoryID)
      rebuildPromptSnapshot(selectPromptID: leadID)
      registerPromptUndo(actionName: NSLocalizedString("Move Prompts", comment: "Undo action")) {
        $0.restorePromptCategories(previousCategories)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func bulkAddPromptTagIDs(_ tagIDs: Set<UUID>) {
    guard !selectedPromptItems.isEmpty, !tagIDs.isEmpty else { return }
    let leadID = leadPromptSelectionID
    let previousTags = Dictionary(uniqueKeysWithValues: selectedPromptItems.map {
      ($0.id, promptSnapshot?.tagIDsByPromptID[$0.id] ?? [])
    })
    do {
      try Diagnostics.measure(Diagnostics.Name.promptBulkTags) {
        try promptOrganizer.addTags(tagIDs, to: selectedPromptItems)
      }
      rebuildPromptSnapshot(selectPromptID: leadID)
      registerPromptUndo(actionName: NSLocalizedString("Add Prompt Tags", comment: "Undo action")) {
        $0.restorePromptTags(previousTags)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func bulkRemovePromptTagIDs(_ tagIDs: Set<UUID>) {
    guard !selectedPromptItems.isEmpty, !tagIDs.isEmpty else { return }
    let leadID = leadPromptSelectionID
    let previousTags = Dictionary(uniqueKeysWithValues: selectedPromptItems.map {
      ($0.id, promptSnapshot?.tagIDsByPromptID[$0.id] ?? [])
    })
    do {
      try Diagnostics.measure(Diagnostics.Name.promptBulkTags) {
        try promptOrganizer.removeTags(tagIDs, from: selectedPromptItems)
      }
      rebuildPromptSnapshot(selectPromptID: leadID)
      registerPromptUndo(actionName: NSLocalizedString("Remove Prompt Tags", comment: "Undo action")) {
        $0.restorePromptTags(previousTags)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func bulkSetFavoriteForSelectedPrompts(_ value: Bool) {
    guard !selectedPromptItems.isEmpty else { return }
    let leadID = leadPromptSelectionID
    let previousFavorites = Dictionary(uniqueKeysWithValues: selectedPromptItems.map { ($0.id, $0.isFavorite) })
    do {
      try promptOrganizer.setFavorite(value, for: selectedPromptItems)
      rebuildPromptSnapshot(selectPromptID: leadID)
      registerPromptUndo(actionName: NSLocalizedString("Favorite Prompts", comment: "Undo action")) {
        $0.restorePromptFavorites(previousFavorites)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func bulkDeleteSelectedPrompts() {
    guard !selectedPromptItems.isEmpty else { return }
    let deletedRecords = selectedPromptItems.map { item in
      DeletedPromptRecord(item: item, tagIDs: promptSnapshot?.tagIDsByPromptID[item.id] ?? [])
    }
    do {
      try promptOrganizer.deletePrompts(selectedPromptItems)
      selectedPromptIDs.removeAll()
      leadPromptSelectionID = nil
      rebuildPromptSnapshot()
      showPromptBulkDeleteConfirmation = false
      registerPromptUndo(actionName: NSLocalizedString("Delete Prompts", comment: "Undo action")) {
        $0.restoreDeletedPrompts(deletedRecords)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  func promptTags(for item: PromptItem?) -> [PromptTag] {
    guard let item else { return [] }
    return promptSnapshot?.tagsByPromptID[item.id] ?? []
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
          categoryID != promptSnapshot?.rootCategoryID else {
      return nil
    }
    return promptSnapshot?.categoryByID[categoryID]?.name
  }

  func promptCategoryName(for item: PromptItem?) -> String {
    let rootName = NSLocalizedString("Prompt Root", comment: "Prompt root category")
    guard let item else { return rootName }
    guard let categoryID = item.categoryID else { return rootName }
    return promptSnapshot?.categoryByID[categoryID]?.name ?? rootName
  }

  func setPromptCategoryFilter(_ categoryFilter: PromptCategoryFilter) {
    promptFilter.categoryFilter = categoryFilter
    updatePromptVisibility()
  }

  func setPromptSortOrder(_ sortOrder: PromptSortOrder) {
    promptFilter.sortOrder = sortOrder
    updatePromptVisibility()
  }

  func clearPromptFilters() {
    promptFilter.searchQuery = ""
    promptFilter.categoryFilter = .all
    promptFilter.selectedTagIDs.removeAll()
    updatePromptVisibility()
  }

  func categoryCount(_ categoryID: UUID) -> Int {
    promptSnapshot?.categoryCounts[categoryID] ?? 0
  }

  var promptRootCategoryID: UUID? {
    promptSnapshot?.rootCategoryID
  }

  var promptCategoryFilterTitle: String? {
    switch promptFilter.categoryFilter {
    case .all:
      return nil
    case .root:
      return NSLocalizedString("Prompt Root", comment: "Prompt root filter")
    case .category(let categoryID):
      return promptSnapshot?.categoryByID[categoryID]?.name
    }
  }

  func tagCount(_ tagID: UUID) -> Int {
    promptSnapshot?.tagCounts[tagID] ?? 0
  }

  func promptTagSelectionState(_ tagID: UUID) -> PromptTagSelectionState {
    guard !selectedPromptItems.isEmpty else { return .none }
    let matched = selectedPromptItems.reduce(into: 0) { count, item in
      if promptSnapshot?.tagIDsByPromptID[item.id]?.contains(tagID) == true {
        count += 1
      }
    }
    if matched == 0 { return .none }
    if matched == selectedPromptItems.count { return .all }
    return .some
  }

  func isPromptCategoryFilterSelected(_ filter: PromptCategoryFilter) -> Bool {
    promptFilter.categoryFilter == filter
  }

  func selectPromptRootCategory() {
    setPromptCategoryFilter(.root)
  }

  func selectAllPrompts() {
    setPromptCategoryFilter(.all)
  }

  func selectPromptCategory(_ categoryID: UUID) {
    setPromptCategoryFilter(.category(categoryID))
  }

  func refreshPromptSelectionAfterFilterChange() {
    syncPromptSelectionAfterVisibilityChange()
    popup.needsResize = true
  }

  func togglePromptTagFilter(_ tagID: UUID) {
    if promptFilter.selectedTagIDs.contains(tagID) {
      promptFilter.selectedTagIDs.remove(tagID)
    } else {
      promptFilter.selectedTagIDs.insert(tagID)
    }
    updatePromptVisibility()
  }

  private func rebuildPromptSnapshot(selectPromptID: UUID? = nil) {
    capturePromptLoadError()
    promptSnapshot = PromptSnapshot(
      items: promptLibrary.items,
      categories: promptCategoryStore.categories,
      tags: promptTagStore.tags,
      links: promptTagStore.links
    )
    updatePromptVisibility(selectPromptID: selectPromptID)
  }

  private var defaultPromptCategoryID: UUID? {
    switch promptFilter.categoryFilter {
    case .category(let categoryID):
      return categoryID
    case .all, .root:
      return promptSnapshot?.rootCategoryID ?? promptCategoryStore.rootPromptCategory()?.id
    }
  }

  private func schedulePromptVisibilityUpdate() {
    promptSearchTask?.cancel()
    promptSearchTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      self?.updatePromptVisibility()
    }
  }

  private func flushPromptSearch() {
    promptSearchTask?.cancel()
    promptSearchTask = nil
    updatePromptVisibility()
  }

  private func updatePromptVisibility(selectPromptID: UUID? = nil) {
    guard let promptSnapshot else {
      cachedVisiblePromptItems = []
      unknownPromptTagNames = []
      promptSearchHasUnterminatedQuote = false
      return
    }

    let result = Diagnostics.measure(Diagnostics.Name.promptSearch) {
      promptSnapshot.result(
        searchQuery: promptFilter.searchQuery,
        favoritesOnly: promptFilter.favoritesOnly,
        categoryFilter: promptFilter.categoryFilter,
        selectedTagIDs: promptFilter.selectedTagIDs,
        sortOrder: promptFilter.sortOrder
      )
    }
    cachedVisiblePromptItems = result.items
    unknownPromptTagNames = result.unknownTagNames
    promptSearchHasUnterminatedQuote = result.hasUnterminatedQuote
    promptListRevision &+= 1

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

  private var currentPromptSelectionState: PromptSelectionState {
    PromptSelectionState(
      selectedIDs: selectedPromptIDs,
      leadID: leadPromptSelectionID,
      anchorID: promptSelectionAnchorID
    )
  }

  private func applyPromptSelectionState(_ state: PromptSelectionState) {
    selectedPromptIDs = state.selectedIDs
    leadPromptSelectionID = state.leadID
    promptSelectionAnchorID = state.anchorID
    selectedPromptItem = state.leadID.flatMap { leadID in
      visiblePromptItems.first(where: { $0.id == leadID })
    }
    preservePromptSelectionDuringSelectionChange = true
    selection = state.leadID
    preservePromptSelectionDuringSelectionChange = false
    popup.needsResize = true
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
      promptExpandedMinWidth: promptExpandedMinWidth,
      promptMinimumHeight: promptMinimumHeight
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
        if let anchor = promptSelectionAnchorID, !kept.contains(anchor) {
          promptSelectionAnchorID = newLead
        }
        selectedPromptItem = visiblePromptItems.first(where: { $0.id == newLead })
        preservePromptSelectionDuringSelectionChange = true
        selection = newLead
        preservePromptSelectionDuringSelectionChange = false
        return
      }
    }

    selectedPromptIDs.removeAll()
    leadPromptSelectionID = nil
    promptSelectionAnchorID = nil
    if let first = visiblePromptItems.first {
      preservePromptSelectionDuringSelectionChange = false
      selection = first.id
    } else {
      selectedPromptItem = nil
      selection = nil
    }
  }

  private var promptUndoManager: UndoManager? {
    appDelegate?.panel?.undoManager ?? NSApp.keyWindow?.undoManager ?? fallbackPromptUndoManager
  }

  private func registerPromptUndo(actionName: String, _ action: @escaping (AppState) -> Void) {
    guard let promptUndoManager else { return }
    promptUndoManager.registerUndo(withTarget: self) { target in
      action(target)
    }
    promptUndoManager.setActionName(actionName)
  }

  private func restorePromptCategories(_ categoriesByPromptID: [UUID: UUID?]) {
    let inverse = Dictionary(uniqueKeysWithValues: promptLibrary.items.compactMap { item in
      categoriesByPromptID.keys.contains(item.id) ? (item.id, item.categoryID) : nil
    })
    let validCategoryIDs = Set(promptCategoryStore.categories.map(\.id))
    for item in promptLibrary.items {
      guard let category = categoriesByPromptID[item.id] else { continue }
      if let category, validCategoryIDs.contains(category) {
        item.categoryID = category
      } else {
        item.categoryID = promptSnapshot?.rootCategoryID
      }
      item.updatedAt = .now
    }
    if savePromptUndoMutation() {
      registerPromptUndo(actionName: NSLocalizedString("Move Prompts", comment: "Undo action")) {
        $0.restorePromptCategories(inverse)
      }
    }
  }

  private func restorePromptTags(_ tagsByPromptID: [UUID: Set<UUID>]) {
    let inverse = Dictionary(uniqueKeysWithValues: tagsByPromptID.keys.map { promptID in
      (promptID, promptSnapshot?.tagIDsByPromptID[promptID] ?? [])
    })
    let validPromptIDs = Set(promptLibrary.items.map(\.id))
    do {
      for (promptID, tagIDs) in tagsByPromptID {
        try promptTagStore.applyTagIDs(tagIDs, for: promptID, validPromptIDs: validPromptIDs)
      }
      try promptLibrary.context.save()
      reloadPromptStoresAndSnapshot()
      registerPromptUndo(actionName: NSLocalizedString("Edit Prompt Tags", comment: "Undo action")) {
        $0.restorePromptTags(inverse)
      }
    } catch {
      promptLibrary.context.rollback()
      promptErrorMessage = error.localizedDescription
      reloadPromptStoresAndSnapshot()
    }
  }

  private func restorePromptFavorites(_ favoritesByPromptID: [UUID: Bool]) {
    let inverse = Dictionary(uniqueKeysWithValues: promptLibrary.items.compactMap { item in
      favoritesByPromptID.keys.contains(item.id) ? (item.id, item.isFavorite) : nil
    })
    for item in promptLibrary.items {
      if let isFavorite = favoritesByPromptID[item.id] {
        item.isFavorite = isFavorite
        item.updatedAt = .now
      }
    }
    if savePromptUndoMutation() {
      registerPromptUndo(actionName: NSLocalizedString("Favorite Prompts", comment: "Undo action")) {
        $0.restorePromptFavorites(inverse)
      }
    }
  }

  private func restoreDeletedPrompts(_ records: [DeletedPromptRecord]) {
    let existingIDs = Set(promptLibrary.items.map(\.id))
    let validCategoryIDs = Set(promptCategoryStore.categories.map(\.id))
    for record in records where !existingIDs.contains(record.id) {
      let categoryID = record.categoryID.flatMap { validCategoryIDs.contains($0) ? $0 : nil } ??
        promptSnapshot?.rootCategoryID
      let item = PromptItem(
        id: record.id,
        title: record.title,
        plainText: record.plainText,
        normalizedText: record.normalizedText,
        isFavorite: record.isFavorite,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
        lastUsedAt: record.lastUsedAt,
        usageCount: record.usageCount,
        sourceHistoryItemID: record.sourceHistoryItemID,
        categoryID: categoryID
      )
      promptLibrary.context.insert(item)
      for tagID in record.tagIDs where promptTagStore.tagByID[tagID] != nil {
        promptLibrary.context.insert(PromptItemTagLink(promptItemID: record.id, promptTagID: tagID))
      }
    }
    if savePromptUndoMutation() {
      registerPromptUndo(actionName: NSLocalizedString("Delete Prompts", comment: "Undo action")) {
        $0.deletePromptsForUndo(Set(records.map(\.id)))
      }
    }
  }

  private func deletePromptsForUndo(_ promptIDs: Set<UUID>) {
    let items = promptLibrary.items.filter { promptIDs.contains($0.id) }
    let records = items.map { item in
      DeletedPromptRecord(item: item, tagIDs: promptSnapshot?.tagIDsByPromptID[item.id] ?? [])
    }
    do {
      try promptOrganizer.deletePrompts(items)
      rebuildPromptSnapshot()
      registerPromptUndo(actionName: NSLocalizedString("Delete Prompts", comment: "Undo action")) {
        $0.restoreDeletedPrompts(records)
      }
    } catch {
      promptErrorMessage = error.localizedDescription
    }
  }

  @discardableResult
  private func savePromptUndoMutation() -> Bool {
    do {
      try promptLibrary.context.save()
      reloadPromptStoresAndSnapshot()
      return true
    } catch {
      promptLibrary.context.rollback()
      promptErrorMessage = error.localizedDescription
      reloadPromptStoresAndSnapshot()
      return false
    }
  }

  private func reloadPromptStoresAndSnapshot() {
    promptCategoryStore.load()
    promptTagStore.load()
    promptLibrary.load()
    capturePromptLoadError()
    rebuildPromptSnapshot()
  }

  private func capturePromptLoadError() {
    let loadErrorMessage = promptCategoryStore.loadErrorMessage ??
      promptTagStore.loadErrorMessage ??
      promptLibrary.loadErrorMessage

    if let loadErrorMessage {
      promptErrorMessage = loadErrorMessage
      lastPromptLoadErrorMessage = loadErrorMessage
    } else if promptErrorMessage == lastPromptLoadErrorMessage {
      promptErrorMessage = nil
      lastPromptLoadErrorMessage = nil
    }
  }
}

private struct DeletedPromptRecord {
  let id: UUID
  let title: String
  let plainText: String
  let normalizedText: String
  let isFavorite: Bool
  let createdAt: Date
  let updatedAt: Date
  let lastUsedAt: Date?
  let usageCount: Int
  let sourceHistoryItemID: String?
  let categoryID: UUID?
  let tagIDs: Set<UUID>

  init(item: PromptItem, tagIDs: Set<UUID>) {
    id = item.id
    title = item.title
    plainText = item.plainText
    normalizedText = item.normalizedText
    isFavorite = item.isFavorite
    createdAt = item.createdAt
    updatedAt = item.updatedAt
    lastUsedAt = item.lastUsedAt
    usageCount = item.usageCount
    sourceHistoryItemID = item.sourceHistoryItemID
    categoryID = item.categoryID
    self.tagIDs = tagIDs
  }
}
