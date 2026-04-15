import Cocoa

class About {
  private let repositoryURL = URL(string: "https://github.com/izscc/iMaccy")!
  private let issuesURL = URL(string: "https://github.com/izscc/iMaccy/issues")!
  private let projectDescription = NSAttributedString(
    string: "iMaccy 是一个基于 Maccy 演进的 macOS 剪贴板工作台，重点强化 Prompt 的沉淀、组织与复用。",
    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  )

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
    credits.append(projectDescription)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(links)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
