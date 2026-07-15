import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool

  private var activeSearchBinding: Binding<String> {
    Binding(
      get: { appState.activeSearchQuery },
      set: { appState.activeSearchQuery = $0 }
    )
  }

  var body: some View {
    ZStack {
      VisualEffectView()

      VStack(alignment: .leading, spacing: 0) {
        KeyHandlingView(searchQuery: activeSearchBinding, searchFocused: $searchFocused) {
          HeaderView(
            searchFocused: $searchFocused,
            searchQuery: activeSearchBinding
          )

          if appState.currentScope == .history {
            HistoryListView(
              searchQuery: activeSearchBinding,
              searchFocused: $searchFocused
            )
          } else {
            PromptWorkspaceView(searchFocused: $searchFocused)
          }

          if appState.currentScope == .history {
            FooterView(footer: appState.footer)
          } else {
            Color.clear
              .frame(height: 0)
              .task {
                appState.popup.footerHeight = 0
              }
          }
        }
      }
      .animation(.default.speed(3), value: appState.history.listRevision)
      .animation(.default.speed(3), value: appState.promptListRevision)
      .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
      .padding(.horizontal, 5)
      .padding(.vertical, appState.popup.verticalPadding)
      .onAppear {
        searchFocused = true
      }
      .onMouseMove {
        appState.isKeyboardNavigating = false
      }
      .task {
        if appState.currentScope != .history {
          appState.ensurePromptLibraryLoaded()
        }
      }
    }
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: .panelLifecyclePhaseDidChange)) {
      switch $0.panelLifecyclePhase {
      case .active:
        scenePhase = .active
      case .background:
        scenePhase = .background
      case nil:
        break
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) {
      if let popover = $0.object as? NSPopover {
        // Prevent NSPopover from showing close animation when
        // quickly toggling FloatingPanel while popover is visible.
        popover.animates = false
        // Prevent NSPopover from becoming first responder.
        popover.behavior = .semitransient
      }
    }
    .alert("操作失败", isPresented: Binding(
      get: { appState.promptErrorMessage != nil },
      set: { if !$0 { appState.clearPromptError() } }
    )) {
      Button("确定", role: .cancel) {}
    } message: {
      Text(appState.promptErrorMessage ?? "")
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "zh-Hans"))
    .modelContainer(Storage.shared.container)
}
