import SwiftUI

struct PromptWorkspaceView: View {
  @FocusState.Binding var searchFocused: Bool
  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase
  @State private var sheet: PromptEditorSheet?
  @State private var showInspector = true

  private var showBulkDelete: Binding<Bool> {
    Binding(
      get: { appState.showPromptBulkDeleteConfirmation },
      set: { isPresented in
        if isPresented {
          appState.requestBulkDeleteSelectedPrompts()
        } else {
          appState.showPromptBulkDeleteConfirmation = false
        }
      }
    )
  }

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 8) {
        PromptSidebarView(sheet: $sheet)
          .frame(minWidth: 170, idealWidth: 220, maxWidth: 260)
        Divider()
        VStack(spacing: 8) {
          PromptFilterBar(showInspector: $showInspector)
          if appState.isPromptMultiSelecting {
            PromptBulkActionBar(sheet: $sheet, showDelete: showBulkDelete)
          }
          PromptListView()
        }
        if showInspector && geometry.size.width >= 1_000 {
          Divider()
          PromptInspectorView(sheet: $sheet)
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
        }
      }
      .padding(.horizontal, 8)
      .overlay(alignment: .topTrailing) {
        if geometry.size.width < 1_000 {
          VStack(alignment: .trailing, spacing: 6) {
            Button(
              showInspector
                ? NSLocalizedString("隐藏详情", comment: "Prompt inspector")
                : NSLocalizedString("显示详情", comment: "Prompt inspector")
            ) { showInspector.toggle() }
            .buttonStyle(.borderless)
            .padding(6)
            .accessibilityIdentifier("prompt-toggle-inspector")
            if showInspector {
              PromptInspectorView(sheet: $sheet)
                .frame(
                  width: min(340, geometry.size.width * 0.82), height: geometry.size.height * 0.78
                )
                .padding(10)
                .background(.regularMaterial)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(radius: 8)
            }
          }
        }
      }
      .onChange(of: geometry.size.width) { _, width in
        if width < 1_000 { showInspector = false }
      }
    }
    .background {
      GeometryReader { geo in
        Color.clear.task(id: appState.popup.needsResize) {
          try? await Task.sleep(for: .milliseconds(10))
          if appState.popup.needsResize { appState.popup.resize(height: geo.size.height) }
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        searchFocused = true
        appState.isKeyboardNavigating = true
        if appState.selectedPromptItem == nil {
          appState.selectPromptListItem(appState.visiblePromptItems.first)
        }
      }
    }
    .sheet(item: $sheet) { PromptSheetView(sheet: $0) }
    .onReceive(NotificationCenter.default.publisher(for: .promptEditRequested)) { notification in
      if let item = notification.object as? PromptItem { sheet = .editPrompt(item) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .promptTagsEditRequested)) {
      notification in
      if let item = notification.object as? PromptItem { sheet = .editTags(item) }
    }
    .alert("删除 Prompt", isPresented: showBulkDelete) {
      Button("取消", role: .cancel) {}
      Button("删除", role: .destructive) { appState.bulkDeleteSelectedPrompts() }
    } message: {
      Text(
        String(
          format: NSLocalizedString(
            "确定删除已选中的 %lld 个 Prompt 吗？删除后可以通过“编辑 > 撤销”恢复。",
            comment: "Bulk Prompt delete confirmation"
          ),
          Int64(appState.selectedPromptIDs.count)
        )
      )
    }
  }
}
