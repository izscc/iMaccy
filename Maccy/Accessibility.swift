import ApplicationServices
import AppKit

struct Accessibility {
  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  )
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  @discardableResult
  static func check(prompt: Bool = true) -> Bool {
    guard !allowed else {
      DebugPasteLog.write("Accessibility.check allowed=true")
      return true
    }

    if prompt {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
      DebugPasteLog.write("Accessibility.check requested prompt")
    }

    let trusted = AXIsProcessTrusted()
    DebugPasteLog.write("Accessibility.check trusted=\(trusted)")
    if !trusted, let settingsURL {
      NSWorkspace.shared.open(settingsURL)
    }

    return trusted
  }
}
