import Defaults
import SwiftUI

struct HistoryListView: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.pinTo) private var pinTo
  @Default(.previewDelay) private var previewDelay

  private var pinnedItems: [HistoryItemDecorator] {
    appState.history.pinnedItems.filter(\.isVisible)
  }
  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }
  private var showPinsSeparator: Bool {
    !pinnedItems.isEmpty && !unpinnedItems.isEmpty && appState.history.searchQuery.isEmpty
  }

  var body: some View {
    if pinTo == .top {
      LazyVStack(spacing: 0) {
        ForEach(pinnedItems) { item in
          HistoryItemView(item: item)
        }

        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }

    ScrollView {
      ScrollViewReader { proxy in
        LazyVStack(spacing: 0) {
          ForEach(unpinnedItems) { item in
            HistoryItemView(item: item)
          }
        }
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            proxy.scrollTo(selection)
            appState.scrollTarget = nil
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            searchFocused = true
            HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
            HistoryItemDecorator.previewThrottler.cancel()
            appState.isKeyboardNavigating = true
            appState.selection = appState.history.unpinnedItems.first?.id ?? appState.history.pinnedItems.first?.id
          } else {
            modifierFlags.flags = []
            appState.isKeyboardNavigating = true
          }
        }
        // Calculate the total height inside a scroll view.
        .background {
          GeometryReader { geo in
            Color.clear
              .task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }

                if appState.popup.needsResize {
                  appState.popup.resize(height: geo.size.height)
                }
              }
          }
        }
      }
      .contentMargins(.leading, 10, for: .scrollIndicators)
    }

    if pinTo == .bottom {
      LazyVStack(spacing: 0) {
        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }

        ForEach(pinnedItems) { item in
          HistoryItemView(item: item)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }
  }
}

struct PromptWorkspaceView: View {
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  private var detailWidth: CGFloat {
    max(220, min(280, (Defaults[.windowSize].width * 0.36)))
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      promptList

      Divider()

      PromptDetailView(item: appState.selectedPromptItem)
        .frame(width: detailWidth, alignment: .topLeading)
    }
    .padding(.horizontal, 10)
    .background {
      GeometryReader { geo in
        Color.clear
          .task {
            appState.popup.pinnedItemsHeight = 0
          }
          .task(id: appState.popup.needsResize) {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }

            if appState.popup.needsResize {
              appState.popup.resize(height: geo.size.height)
            }
          }
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        searchFocused = true
        appState.isKeyboardNavigating = true
        if appState.selectedPromptItem == nil {
          appState.selection = appState.visiblePromptItems.first?.id
        }
      } else {
        appState.isKeyboardNavigating = true
      }
    }
  }

  private var promptList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if appState.visiblePromptItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("还没有 Prompt")
                .font(.headline)
              Text("在历史列表中右键任意文本内容，选择“移动到 Prompt…”，就可以把它沉淀到这里。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.horizontal, 10)
          } else {
            ForEach(appState.visiblePromptItems, id: \.id) { item in
              PromptRowView(item: item)
            }
          }
        }
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            proxy.scrollTo(selection)
            appState.scrollTarget = nil
          }
        }
      }
      .contentMargins(.leading, 10, for: .scrollIndicators)
    }
  }
}

struct PromptRowView: View {
  let item: PromptItem

  @Environment(AppState.self) private var appState

  private var rowTitle: String {
    item.isFavorite ? "★ \(item.title)" : item.title
  }

  var body: some View {
    ListItemView(
      id: item.id,
      appIcon: nil,
      image: nil,
      accessoryImage: ColorImage.from(item.title),
      attributedTitle: nil,
      shortcuts: [],
      isSelected: appState.selectedPromptItem?.id == item.id,
      help: nil
    ) {
      Text(verbatim: rowTitle)
    }
    .onTapGesture(count: 2) {
      appState.selectPrompt(item)
    }
    .onTapGesture {
      appState.selection = item.id
    }
    .contextMenu {
      Button(item.isFavorite ? "取消收藏" : "收藏") {
        appState.toggleFavoritePrompt(item)
      }

      Button("从 Prompt 删除", role: .destructive) {
        appState.deletePrompt(item)
      }
    }
  }
}

struct PromptDetailView: View {
  let item: PromptItem?

  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let item {
        Text(item.title)
          .font(.headline)
          .textSelection(.enabled)

        ScrollView {
          Text(item.plainText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity, alignment: .top)

        Divider()

        detailRow(title: "收藏", value: item.isFavorite ? "是" : "否")
        detailRow(title: "来源历史", value: item.sourceHistoryItemID == nil ? "无" : "有")
        detailRow(title: "分类", value: appState.promptCategoryStore.categoryName(for: item.categoryID))
        detailRow(title: "使用次数", value: String(item.usageCount))

        HStack(spacing: 8) {
          Button(item.isFavorite ? "取消收藏" : "收藏") {
            appState.toggleFavoritePrompt(item)
          }

          Button("复制 Prompt") {
            appState.selectPrompt(item)
          }
        }
        .buttonStyle(.bordered)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Prompt 详情")
            .font(.headline)
          Text("选择一个 Prompt 后，可以在这里查看全文、收藏状态和来源历史。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func detailRow(title: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Text(value)
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
  }
}
