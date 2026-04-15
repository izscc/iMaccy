import AppKit
import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var help: LocalizedStringKey?
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: appIcon.nsImage)
            .resizable()
            .frame(width: 15, height: 15)
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        Image(nsImage: accessoryImage)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      if let image {
        Image(nsImage: image)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, title: title)
          .padding(.trailing, 5)
      }

      Spacer()

      if !shortcuts.isEmpty {
        ZStack {
          ForEach(shortcuts) { shortcut in
            KeyboardShortcutView(shortcut: shortcut)
              .opacity(shortcut.isVisible(shortcuts, modifierFlags.flags) ? 1 : 0)
          }
        }
        .padding(.trailing, 10)
      } else {
        Spacer()
          .frame(width: 50)
      }
    }
    .frame(minHeight: 22)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
    .clipShape(.rect(cornerRadius: 4))
    .onHover { hovering in
      if hovering {
        if appState.currentScope != .history && appState.isPromptMultiSelecting {
          return
        }
        if !appState.isKeyboardNavigating {
          appState.selectWithoutScrolling(id)
        } else {
          appState.hoverSelectionWhileKeyboardNavigating = id
        }
      }
    }
    .help(help ?? "")
  }
}

struct ItemClickCapture: NSViewRepresentable {
  let onSingleClick: (NSEvent.ModifierFlags) -> Void
  var onDoubleClick: (() -> Void)?

  func makeNSView(context: Context) -> ClickCaptureView {
    let view = ClickCaptureView()
    view.onSingleClick = onSingleClick
    view.onDoubleClick = onDoubleClick
    return view
  }

  func updateNSView(_ nsView: ClickCaptureView, context: Context) {
    nsView.onSingleClick = onSingleClick
    nsView.onDoubleClick = onDoubleClick
  }

  final class ClickCaptureView: NSView {
    var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard let event = NSApp.currentEvent else {
        return self
      }

      switch event.type {
      case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
        return nil
      default:
        return self
      }
    }

    override func mouseUp(with event: NSEvent) {
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if event.clickCount >= 2 {
        if let onDoubleClick {
          onDoubleClick()
        } else {
          onSingleClick?(modifiers)
        }
      } else {
        onSingleClick?(modifiers)
      }
    }
  }
}
