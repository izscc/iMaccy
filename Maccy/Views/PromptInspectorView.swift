import SwiftUI

struct PromptInspectorView: View {
  @Environment(AppState.self) private var appState
  @Binding var sheet: PromptEditorSheet?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let item = appState.selectedPromptItem {
        HStack {
          Text(item.title).font(.headline).lineLimit(2)
          Spacer()
          Button("编辑") { sheet = .editPrompt(item) }
            .accessibilityIdentifier("prompt-edit-button")
        }
        ScrollView {
          Text(item.plainText).frame(maxWidth: .infinity, alignment: .leading).textSelection(
            .enabled)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        Divider()
        Toggle(
          "收藏",
          isOn: Binding(get: { item.isFavorite }, set: { _ in appState.toggleFavoritePrompt(item) })
        )
        .toggleStyle(.switch)
        .accessibilityIdentifier("prompt-favorite-toggle")
        Picker(
          "子书签",
          selection: Binding<UUID?>(
            get: {
              appState.promptCategoryStore.bookmarkCategories.contains(where: {
                $0.id == item.categoryID
              }) ? item.categoryID : nil
            },
            set: { appState.assignPromptToCategory(item, categoryID: $0) }
          )
        ) {
          Text("Prompt 根目录").tag(Optional<UUID>.none)
          ForEach(appState.promptCategoryStore.bookmarkCategories, id: \.id) { category in
            Text(category.name).tag(Optional(category.id))
          }
        }
        .accessibilityIdentifier("prompt-category-picker")
        Button("编辑标签") { sheet = .editTags(item) }.buttonStyle(.borderless)
        detailRow("归属", appState.promptCategoryName(for: item))
        detailRow("使用次数", String(item.usageCount))
        if !appState.promptTags(for: item).isEmpty {
          ScrollView(.horizontal) {
            HStack {
              ForEach(appState.promptTags(for: item), id: \.id) {
                PromptMetaChip(title: "#\($0.name)")
              }
            }
          }
        }
        HStack {
          Button("复制") { appState.copyPrompt(item) }
            .accessibilityIdentifier("prompt-copy-button")
          Button("粘贴并关闭") { appState.pastePrompt(item) }
            .accessibilityIdentifier("prompt-paste-button")
          Button("复制副本") {
            do {
              _ = try appState.duplicatePrompt(item)
            } catch {
              appState.promptErrorMessage = error.localizedDescription
            }
          }
        }
        .buttonStyle(.bordered)
      } else {
        Text("Prompt 详情").font(.headline)
        Text("选择一个 Prompt 查看详情。").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityIdentifier("prompt-inspector")
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value)
    }.font(.subheadline)
  }
}
