import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      if showTitle {
        Text("iMaccy")
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize()
      }

      Picker("范围", selection: Binding(
        get: { appState.currentScope },
        set: { appState.currentScope = $0 }
      )) {
        ForEach(LibraryScope.allCases) { scope in
          Text(scope.title).tag(scope)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .fixedSize(horizontal: true, vertical: false)

      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(minWidth: 170, maxWidth: .infinity)
        .frame(width: appState.searchVisible ? nil : 0)
        .opacity(appState.searchVisible ? 1 : 0)
        .onChange(of: scenePhase) {
          if scenePhase == .background && !searchQuery.isEmpty {
            searchQuery = ""
          }
        }
    }
    .padding(.horizontal, 10)
    .padding(.top, 2)
    .padding(.bottom, 6)
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.headerHeight = geo.size.height
          }
      }
    }
  }
}
