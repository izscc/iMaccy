import SwiftUI

enum PromptEditorSheet: Identifiable {
  case createPrompt
  case editPrompt(PromptItem)
  case createBookmark
  case renameBookmark(PromptCategory)
  case createTag
  case renameTag(PromptTag)
  case editTags(PromptItem)
  case bulkAddTags
  case bulkRemoveTags

  var id: String {
    switch self {
    case .createPrompt: return "createPrompt"
    case .editPrompt(let item): return "editPrompt-\(item.id)"
    case .createBookmark: return "createBookmark"
    case .renameBookmark(let item): return "renameBookmark-\(item.id)"
    case .createTag: return "createTag"
    case .renameTag(let item): return "renameTag-\(item.id)"
    case .editTags(let item): return "editTags-\(item.id)"
    case .bulkAddTags: return "bulkAddTags"
    case .bulkRemoveTags: return "bulkRemoveTags"
    }
  }
}

struct PromptSheetView: View {
  let sheet: PromptEditorSheet
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var error: String?

  var body: some View {
    switch sheet {
    case .createPrompt: PromptEditorView(item: nil)
    case .editPrompt(let item): PromptEditorView(item: item)
    case .createBookmark:
      nameSheet("新建子书签") {
        try appState.createPromptBookmark(name: name)
        dismiss()
      }
    case .renameBookmark(let category):
      nameSheet("重命名子书签", initial: category.name) {
        try appState.renamePromptBookmark(category, name: name)
        dismiss()
      }
    case .createTag:
      nameSheet("新建标签") {
        try appState.createPromptTag(name: name)
        dismiss()
      }
    case .renameTag(let tag):
      nameSheet("重命名标签", initial: tag.name) {
        try appState.renamePromptTag(tag, name: name)
        dismiss()
      }
    case .editTags(let item): PromptTagAssignmentSheet(promptItem: item)
    case .bulkAddTags: PromptBulkTagSheet(mode: .add)
    case .bulkRemoveTags: PromptBulkTagSheet(mode: .remove)
    }
  }

  @ViewBuilder
  private func nameSheet(
    _ title: String,
    initial: String = "",
    submit: @escaping () throws -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      TextField("名称", text: $name).textFieldStyle(.roundedBorder)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存") {
          do {
            try submit()
          } catch {
            self.error = error.localizedDescription
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20).frame(width: 340)
    .onAppear { if name.isEmpty { name = initial } }
  }
}

struct PromptTagAssignmentSheet: View {
  let promptItem: PromptItem
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var selected: Set<UUID> = []
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("编辑标签").font(.headline)
      ForEach(appState.promptTagStore.tags, id: \.id) { tag in
        Toggle(
          tag.name,
          isOn: Binding(
            get: { selected.contains(tag.id) },
            set: { isSelected in
              if isSelected {
                selected.insert(tag.id)
              } else {
                selected.remove(tag.id)
              }
            }
          )
        )
        .toggleStyle(.checkbox)
      }
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存") {
          appState.setPromptTagIDs(promptItem, tagIDs: selected)
          dismiss()
        }
      }
    }
    .padding(20).frame(width: 360)
    .task { selected = Set(appState.promptTags(for: promptItem).map(\.id)) }
  }
}

struct PromptBulkTagSheet: View {
  enum Mode: Equatable { case add, remove }
  let mode: Mode
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var selected: Set<UUID> = []
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        mode == .add
          ? NSLocalizedString("批量添加标签", comment: "Bulk Prompt tag sheet")
          : NSLocalizedString("批量移除标签", comment: "Bulk Prompt tag sheet")
      )
      .font(.headline)
      ForEach(appState.promptTagStore.tags, id: \.id) { tag in
        Button {
          if selected.contains(tag.id) {
            selected.remove(tag.id)
          } else {
            selected.insert(tag.id)
          }
        } label: {
          Label(tag.name, systemImage: symbolName(for: tag.id))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: tag))
      }
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存") {
          if mode == .add {
            appState.bulkAddPromptTagIDs(selected)
          } else {
            appState.bulkRemovePromptTagIDs(selected)
          }
          dismiss()
        }
      }
    }
    .padding(20).frame(width: 360)
  }

  private func symbolName(for tagID: UUID) -> String {
    if selected.contains(tagID) { return "checkmark.square.fill" }
    switch appState.promptTagSelectionState(tagID) {
    case .none: return "square"
    case .some: return "minus.square"
    case .all: return "checkmark.square"
    }
  }

  private func accessibilityLabel(for tag: PromptTag) -> String {
    let state: String
    switch appState.promptTagSelectionState(tag.id) {
    case .none: state = NSLocalizedString("未选中", comment: "Prompt tag selection state")
    case .some:
      state = NSLocalizedString("部分 Prompt 已选中", comment: "Prompt tag selection state")
    case .all:
      state = NSLocalizedString("所有 Prompt 已选中", comment: "Prompt tag selection state")
    }
    return String(
      format: NSLocalizedString("%@，%@", comment: "Prompt tag accessibility label"),
      tag.name,
      state
    )
  }
}
