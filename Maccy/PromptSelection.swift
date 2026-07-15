import Foundation

struct PromptSelectionState: Equatable {
  var selectedIDs: Set<UUID> = []
  var leadID: UUID?
  var anchorID: UUID?
}

enum PromptSelectionReducer {
  static func single(_ id: UUID?) -> PromptSelectionState {
    guard let id else { return PromptSelectionState() }
    return PromptSelectionState(selectedIDs: [id], leadID: id, anchorID: id)
  }

  static func toggle(_ id: UUID, state: PromptSelectionState, visibleIDs: [UUID])
    -> PromptSelectionState
  {
    var next = state
    if next.selectedIDs.remove(id) != nil {
      if next.selectedIDs.isEmpty {
        return PromptSelectionState()
      }
      if next.leadID == id {
        next.leadID = visibleIDs.first(where: next.selectedIDs.contains)
      }
    } else {
      next.selectedIDs.insert(id)
      next.leadID = id
      next.anchorID = next.anchorID ?? id
    }
    return next
  }

  static func range(
    to id: UUID,
    state: PromptSelectionState,
    visibleIDs: [UUID]
  ) -> PromptSelectionState {
    guard let anchorID = state.anchorID ?? state.leadID,
      let anchorIndex = visibleIDs.firstIndex(of: anchorID),
      let targetIndex = visibleIDs.firstIndex(of: id)
    else {
      return single(id)
    }

    let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
    return PromptSelectionState(
      selectedIDs: Set(range.map { visibleIDs[$0] }),
      leadID: id,
      anchorID: anchorID
    )
  }

  static func selectAll(_ visibleIDs: [UUID], preferredLeadID: UUID?) -> PromptSelectionState {
    guard let first = visibleIDs.first else { return PromptSelectionState() }
    let lead = preferredLeadID.flatMap { visibleIDs.contains($0) ? $0 : nil } ?? first
    return PromptSelectionState(selectedIDs: Set(visibleIDs), leadID: lead, anchorID: first)
  }
}

enum PromptTagSelectionState: Equatable {
  case none
  case some
  case all
}
