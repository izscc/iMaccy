import AppKit.NSRunningApplication
import Defaults
import Foundation
import Observation
import Sauce
import Settings
import SwiftData

@MainActor
@Observable
class History { // swiftlint:disable:this type_body_length
  static let shared = History()

  var items: [HistoryItemDecorator] = [] {
    didSet { listRevision &+= 1 }
  }
  var listRevision = 0
  var selectedItem: HistoryItemDecorator? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        Diagnostics.measure(Diagnostics.Name.historySearch) {
          updateItems(search.search(string: searchQuery, within: all))

          if searchQuery.isEmpty {
            AppState.shared.selection = unpinnedItems.first?.id
          } else {
            AppState.shared.highlightFirst()
          }

          AppState.shared.popup.needsResize = true
        }
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]
  @ObservationIgnored
  private var unpinnedCount = 0

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  init() {
    Task { [weak self] in
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        guard let self else { return }
        self.updateShortcuts()
      }
    }

    Task { [weak self] in
      for await _ in Defaults.updates(.sortBy, initial: false) {
        guard let self else { return }
        try? await self.load()
      }
    }

    Task { [weak self] in
      for await _ in Defaults.updates(.pinTo, initial: false) {
        guard let self else { return }
        try? await self.load()
      }
    }

    Task { [weak self] in
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        guard let self else { return }
        self.items.forEach { item in
          let title = item.item.generateTitle()
          item.title = title
          item.item.title = title
        }
      }
    }

    Task { [weak self] in
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        guard let self else { return }
        for item in self.items {
          await item.sizeImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    let interval = Diagnostics.begin(Diagnostics.Name.historyLoad)
    defer { Diagnostics.end(Diagnostics.Name.historyLoad, interval) }

    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    unpinnedCount = all.reduce(into: 0) { count, item in
      if item.isUnpinned {
        count += 1
      }
    }
    items = all

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    let interval = Diagnostics.begin(Diagnostics.Name.historyAdd)
    defer { Diagnostics.end(Diagnostics.Name.historyAdd, interval) }

    while unpinnedCount >= Defaults[.size],
          let oldestUnpinnedItem = all.last(where: \.isUnpinned) {
      delete(oldestUnpinnedItem)
    }

    var removedItemIndex: Int?
    var replacedSelectedItem = false
    if let existingHistoryItem = findSimilarItem(item) {
      replacedSelectedItem = selectedItem?.item == existingHistoryItem
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      Storage.shared.context.delete(existingHistoryItem)
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
      if let removedItemIndex {
        if all[removedItemIndex].isUnpinned {
          unpinnedCount = max(0, unpinnedCount - 1)
        }
        all.remove(at: removedItemIndex)
      }
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if let pin = item.pin {
      itemDecorator = HistoryItemDecorator(item, shortcuts: KeyShortcut.create(character: pin))
      // Keep pins in the same place.
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)
      unpinnedCount += 1

      let sortedItems = sorter.sort(all.map(\.item) + [item])
      if let index = sortedItems.firstIndex(of: item) {
        all.insert(itemDecorator, at: index)
      }

    }

    items = all
    if replacedSelectedItem {
      selectedItem = itemDecorator
      AppState.shared.selection = itemDecorator.id
    }
    if itemDecorator.isUnpinned {
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    }

    return itemDecorator
  }

  @MainActor
  func clear() {
    all.removeAll(where: \.isUnpinned)
    unpinnedCount = 0
    items = all
    try? Storage.shared.context.delete(
      model: HistoryItem.self,
      where: #Predicate { $0.pin == nil }
    )
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    all.removeAll()
    unpinnedCount = 0
    items = all
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    Storage.shared.context.delete(item.item)
    if item.isUnpinned {
      unpinnedCount = max(0, unpinnedCount - 1)
    }
    all.removeAll { $0 == item }
    items.removeAll { $0 == item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    DebugPasteLog.write("History.select")

    let modifierFlags = NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []

    let action: ItemAction
    let removeFormatting: Bool
    if modifierFlags.isEmpty {
      action = Defaults[.pasteByDefault] ? .paste : .copy
      removeFormatting = Defaults[.removeFormattingByDefault]
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        action = .copy
        removeFormatting = false
      case .paste:
        action = .paste
        removeFormatting = false
      case .pasteWithoutFormatting:
        action = .pasteWithoutFormatting
        removeFormatting = true
      case .unknown:
        return
      }
    }

    perform(action, on: item, source: .keyboard, removeFormatting: removeFormatting)
  }

  @MainActor
  func selectFromPointer(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    DebugPasteLog.write("History.selectFromPointer")
    let action: ItemAction = Defaults[.pasteByDefault] ? .paste : .copy
    perform(
      action,
      on: item,
      source: .pointer,
      removeFormatting: Defaults[.removeFormattingByDefault]
    )
  }

  private func perform(
    _ action: ItemAction,
    on item: HistoryItemDecorator,
    source: ActivationSource,
    removeFormatting: Bool
  ) {
    if action != .copy {
      _ = Accessibility.check()
    }
    AppState.shared.itemActionCoordinator.perform(action, source: source) {
      Clipboard.shared.copy(item.item, removeFormatting: removeFormatting)
    }
    searchQuery = ""
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let wasUnpinned = item.isUnpinned
    item.togglePin()
    if wasUnpinned && item.isPinned {
      unpinnedCount = max(0, unpinnedCount - 1)
    } else if !wasUnpinned && item.isUnpinned {
      unpinnedCount += 1
    }

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    items = all

    searchQuery = ""
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.scrollTarget = item.id
    }
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    if let existing = Self.findSimilarItem(item, in: all.lazy.map(\.item)) {
      return existing
    }

    return isModified(item)
  }

  static func findSimilarItem<Items: Sequence>(_ item: HistoryItem, in items: Items) -> HistoryItem?
  where Items.Element == HistoryItem {
    items.lazy.first(where: { $0 == item || $0.supersedes(item) })
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(10) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
