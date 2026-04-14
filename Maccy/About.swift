import Cocoa

class About {
  private let repositoryURL = URL(string: "https://github.com/izscc/iMaccy")!
  private let issuesURL = URL(string: "https://github.com/izscc/iMaccy/issues")!

  private let familyCredits = NSAttributedString(
    string: "Special thank you to Tonia, Anna & Guy! ❤️",
    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  )

  private var kossCredits: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Kudos to Sasha Koss for help! 🏂",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://koss.nocorp.me", range: NSRange(location: 9, length: 10))
    return string
  }

  private var links: NSMutableAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
    let string = NSMutableAttributedString()

    func appendLink(title: String, url: URL) {
      let start = string.length
      string.append(NSAttributedString(string: title, attributes: attributes))
      string.addAttribute(.link, value: url, range: NSRange(location: start, length: title.count))
    }

    appendLink(title: "主页", url: repositoryURL)
    string.append(NSAttributedString(string: "│", attributes: attributes))
    appendLink(title: "GitHub", url: repositoryURL)
    string.append(NSAttributedString(string: "│", attributes: attributes))
    appendLink(title: "反馈", url: issuesURL)
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(kossCredits)
    credits.append(NSAttributedString(string: "\n"))
    credits.append(familyCredits)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
