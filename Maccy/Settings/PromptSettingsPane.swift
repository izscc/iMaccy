import Defaults
import Settings
import SwiftUI

struct PromptSettingsPane: View {
  @Default(.defaultLibraryScope) private var defaultLibraryScope
  @Default(.promptRecentBookmarkLimit) private var promptRecentBookmarkLimit
  @Default(.confirmPromptBulkDelete) private var confirmPromptBulkDelete
  @Default(.showPromptCategoryBadge) private var showPromptCategoryBadge
  @Default(.showPromptTagSummary) private var showPromptTagSummary

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("默认打开视图") }
      ) {
        Picker("", selection: $defaultLibraryScope) {
          ForEach(LibraryScope.allCases) { scope in
            Text(scope.title).tag(scope)
          }
        }
        .labelsHidden()
        .frame(width: 180)

        Text("控制每次打开弹窗时默认进入的视图。")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("最近子书签") }
      ) {
        HStack {
          TextField("", value: $promptRecentBookmarkLimit, formatter: numberFormatter)
            .frame(width: 80)
          Stepper("", value: $promptRecentBookmarkLimit, in: 0...5)
            .labelsHidden()
        }
        Text("设置为 0 时，不显示“最近子书签”入口。")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("批量操作") }
      ) {
        Defaults.Toggle(key: .confirmPromptBulkDelete) {
          Text("批量删除前弹出确认")
        }
      }

      Settings.Section(label: { Text("列表显示") }) {
        Defaults.Toggle(key: .showPromptCategoryBadge) {
          Text("显示子书签摘要")
        }
        Defaults.Toggle(key: .showPromptTagSummary) {
          Text("显示标签摘要")
        }
      }
    }
  }

  private var numberFormatter: NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 5
    return formatter
  }
}

#Preview {
  PromptSettingsPane()
}
