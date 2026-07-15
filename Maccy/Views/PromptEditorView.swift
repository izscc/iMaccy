import SwiftUI

struct PromptEditorView: View {
  let item: PromptItem?
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var bodyText: String
  @State private var showDiscard = false
  @State private var errorMessage: String?

  init(item: PromptItem?) {
    self.item = item
    _title = State(initialValue: item?.title ?? "")
    _bodyText = State(initialValue: item?.plainText ?? "")
  }

  private var dirty: Bool {
    title != (item?.title ?? "") || bodyText != (item?.plainText ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(item == nil ? localized("新建 Prompt") : localized("编辑 Prompt")).font(.headline)
      TextField("标题", text: $title).textFieldStyle(.roundedBorder).accessibilityIdentifier(
        "prompt-editor-title")
      TextEditor(text: $bodyText)
        .font(.body)
        .frame(minHeight: 180)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        .accessibilityIdentifier("prompt-editor-body")
      if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("取消") { cancel() }.keyboardShortcut(.cancelAction)
        Button("保存") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(!canSave)
          .accessibilityIdentifier("prompt-editor-save")
      }
    }
    .padding(20)
    .frame(width: 500)
    .confirmationDialog("放弃未保存的修改？", isPresented: $showDiscard) {
      Button("放弃修改", role: .destructive) { dismiss() }
      Button("继续编辑", role: .cancel) {}
    }
    .onExitCommand(perform: cancel)
    .interactiveDismissDisabled(dirty)
  }

  private func cancel() {
    if dirty { showDiscard = true } else { dismiss() }
  }

  private var canSave: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func save() {
    do {
      if let item {
        try appState.updatePrompt(item, title: title, plainText: bodyText)
      } else {
        _ = try appState.createPrompt(title: title, plainText: bodyText)
      }
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "Prompt editor")
  }
}
