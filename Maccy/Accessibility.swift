import ApplicationServices
import AppKit

struct Accessibility {
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  @discardableResult
  static func check(prompt: Bool = true) -> Bool {
    guard !allowed else {
      return true
    }

    if prompt {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }

    return AXIsProcessTrusted()
  }
}
