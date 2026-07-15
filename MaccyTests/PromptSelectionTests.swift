import XCTest

@testable import iMaccy

final class PromptSelectionTests: XCTestCase {
  private let ids = (1...5).map { value in
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }

  func testShiftSelectionUsesStableAnchor() {
    let initial = PromptSelectionReducer.single(ids[1])
    let extended = PromptSelectionReducer.range(to: ids[4], state: initial, visibleIDs: ids)

    XCTAssertEqual(extended.selectedIDs, Set(ids[1...4]))
    XCTAssertEqual(extended.anchorID, ids[1])
    XCTAssertEqual(extended.leadID, ids[4])
  }

  func testCommandToggleRemovesLeadPredictably() {
    var state = PromptSelectionReducer.single(ids[1])
    state = PromptSelectionReducer.toggle(ids[3], state: state, visibleIDs: ids)
    state = PromptSelectionReducer.toggle(ids[3], state: state, visibleIDs: ids)

    XCTAssertEqual(state.selectedIDs, Set([ids[1]]))
    XCTAssertEqual(state.leadID, ids[1])
  }

  func testSelectAllUsesVisibleItemsOnly() {
    let state = PromptSelectionReducer.selectAll(Array(ids.prefix(3)), preferredLeadID: ids[4])

    XCTAssertEqual(state.selectedIDs, Set(ids.prefix(3)))
    XCTAssertEqual(state.leadID, ids[0])
    XCTAssertEqual(state.anchorID, ids[0])
  }
}
