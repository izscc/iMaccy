import Foundation

/// The result of parsing the free-form Prompt search field.
struct PromptSearchResult: Equatable, Sendable {
  let textQuery: String
  let tagNames: [String]
  let hasUnterminatedQuote: Bool

  var unterminatedQuote: Bool { hasUnterminatedQuote }
}

/// Parses text terms and `#tag` / `#"multi word tag"` filters without touching storage.
enum PromptSearchParser {
  static func parse(_ query: String) -> PromptSearchResult {
    var text = String()
    var tags: [String] = []
    var unterminatedQuote = false
    var index = query.startIndex

    func appendText(_ value: Substring) {
      text.append(contentsOf: value)
    }

    while index < query.endIndex {
      guard query[index] == "#" else {
        let start = index
        index = query.index(after: index)
        while index < query.endIndex, query[index] != "#" {
          index = query.index(after: index)
        }
        appendText(query[start..<index])
        continue
      }

      let hash = index
      let afterHash = query.index(after: hash)
      guard afterHash < query.endIndex else {
        appendText(query[hash..<query.endIndex])
        break
      }

      if query[afterHash] == "\"" {
        let startName = query.index(after: afterHash)
        var cursor = startName
        var closingQuote: String.Index?
        while cursor < query.endIndex {
          if query[cursor] == "\"" {
            closingQuote = cursor
            break
          }
          cursor = query.index(after: cursor)
        }

        if let closingQuote {
          let name = String(query[startName..<closingQuote])
          if !name.isEmpty {
            tags.append(name)
            index = query.index(after: closingQuote)
            continue
          }
        } else {
          let name = String(query[startName..<query.endIndex])
          if !name.isEmpty {
            tags.append(name)
          }
          unterminatedQuote = true
          break
        }
      } else {
        var cursor = afterHash
        while cursor < query.endIndex,
          !query[cursor].isWhitespace,
          query[cursor] != "#"
        {
          cursor = query.index(after: cursor)
        }
        if cursor > afterHash {
          tags.append(String(query[afterHash..<cursor]))
          index = cursor
          continue
        }
      }

      // A lone '#' or an empty quoted tag is ordinary text.
      appendText(query[hash..<afterHash])
      index = afterHash
    }

    let normalizedText =
      text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    return PromptSearchResult(
      textQuery: normalizedText,
      tagNames: tags,
      hasUnterminatedQuote: unterminatedQuote
    )
  }
}
