import Sauce
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { _ in
        if appState.appDelegate?.panel?.attachedSheet != nil {
          return .ignored
        }

        // Unfortunately, key presses don't allow access to
        // key code and don't properly work with multiple inputs,
        // so pressing ⌘, on non-English layout doesn't open
        // preferences. Stick to NSEvent to fix this behavior.
        switch KeyChord(NSApp.currentEvent) {
        case .clearHistory:
          guard appState.currentScope == .history else {
            return .ignored
          }

          if let item = appState.footer.items.first(where: { $0.title == "clear" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearHistoryAll:
          guard appState.currentScope == .history else {
            return .ignored
          }

          if let item = appState.footer.items.first(where: { $0.title == "clear_all" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearSearch:
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          switch appState.currentScope {
          case .history:
            if let item = appState.history.selectedItem {
              appState.highlightNext()
              appState.history.delete(item)
            }
          case .prompt, .favorites:
            appState.deleteSelectedPrompt()
          }
          return .handled
        case .deleteOneCharFromSearch:
          searchFocused = true
          _ = searchQuery.popLast()
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          let newQuery = searchQuery.split(separator: " ").dropLast().joined(separator: " ")
          if newQuery.isEmpty {
            searchQuery = ""
          } else {
            searchQuery = "\(newQuery) "
          }

          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          if appState.currentScope != .history,
             NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            appState.extendPromptSelection(by: 1)
          } else {
            appState.highlightNext()
          }
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          if appState.currentScope != .history,
             NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            appState.extendPromptSelection(by: -1)
          } else {
            appState.highlightPrevious()
          }
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          guard appState.currentScope == .history else {
            return .ignored
          }
          appState.history.togglePin(appState.history.selectedItem)
          return .handled
        case .selectAll:
          guard appState.currentScope != .history,
                !searchFocused,
                !isTextInputActive else { return .ignored }
          appState.selectAllVisiblePrompts()
          return .handled
        case .undo:
          guard appState.currentScope != .history,
                !searchFocused,
                !isTextInputActive else { return .ignored }
          appState.undoPromptAction()
          return .handled
        case .redo:
          guard appState.currentScope != .history,
                !searchFocused,
                !isTextInputActive else { return .ignored }
          appState.redoPromptAction()
          return .handled
        case .selectCurrentItem:
          appState.select()
          return .handled
        case .close:
          if appState.currentScope != .history, !appState.selectedPromptIDs.isEmpty {
            appState.clearPromptSelection()
          } else {
            appState.popup.close()
          }
          return .handled
        default:
          ()
        }

        if appState.currentScope == .history,
           let item = appState.history.pressedShortcutItem {
          appState.selection = item.id
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.select(item)
          }
          return .handled
        }

        return .ignored
      }
  }

  private var isTextInputActive: Bool {
    NSApp.keyWindow?.firstResponder is NSTextView
  }
}
