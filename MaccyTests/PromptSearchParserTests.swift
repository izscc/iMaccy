import XCTest

@testable import iMaccy

final class PromptSearchParserTests: XCTestCase {
  func testParsesTextAndSingleWordTags() {
    let result = PromptSearchParser.parse("review #swift #代码")

    XCTAssertEqual(result.textQuery, "review")
    XCTAssertEqual(result.tagNames, ["swift", "代码"])
    XCTAssertFalse(result.hasUnterminatedQuote)
  }

  func testParsesQuotedMultiWordTag() {
    let result = PromptSearchParser.parse("draft #\"代码 审查\" now")

    XCTAssertEqual(result.textQuery, "draft now")
    XCTAssertEqual(result.tagNames, ["代码 审查"])
    XCTAssertFalse(result.hasUnterminatedQuote)
  }

  func testReportsUnterminatedQuotedTag() {
    let result = PromptSearchParser.parse("hello #\"多词标签")

    XCTAssertEqual(result.textQuery, "hello")
    XCTAssertEqual(result.tagNames, ["多词标签"])
    XCTAssertTrue(result.hasUnterminatedQuote)
  }

  func testLoneHashRemainsText() {
    let result = PromptSearchParser.parse("C# #")

    XCTAssertEqual(result.textQuery, "C# #")
    XCTAssertTrue(result.tagNames.isEmpty)
  }
}
