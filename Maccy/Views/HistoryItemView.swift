import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator

  @Environment(AppState.self) private var appState

  private var bookmarks: [PromptCategory] {
    appState.promptCategoryStore.bookmarkCategories
  }
  private var recentBookmarks: [PromptCategory] {
    appState.recentPromptBookmarks
  }

  var body: some View {
    ListItemView(
      id: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected
    ) {
      Text(verbatim: item.title)
    }
    .onTapGesture {
      appState.history.selectFromPointer(item)
    }
    .contextMenu {
      if item.item.promptPlainText != nil {
        Button("移动到 Prompt") {
          appState.archiveHistoryItemToPrompt(item.item)
        }

        if !recentBookmarks.isEmpty {
          Menu("移动到最近子书签") {
            ForEach(recentBookmarks, id: \.id) { bookmark in
              Button(bookmark.name) {
                appState.archiveHistoryItemToPrompt(item.item, categoryID: bookmark.id)
              }
            }
          }
        }

        Menu("移动到子书签") {
          if bookmarks.isEmpty {
            Button("暂无子书签") {}
              .disabled(true)
          } else {
            ForEach(bookmarks, id: \.id) { bookmark in
              Button(bookmark.name) {
                appState.archiveHistoryItemToPrompt(item.item, categoryID: bookmark.id)
              }
            }
          }
        }
      }
    }
    .popover(isPresented: $item.showPreview, arrowEdge: .trailing) {
      PreviewItemView(item: item)
    }
  }
}
