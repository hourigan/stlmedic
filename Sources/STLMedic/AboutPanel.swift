import AppKit

enum AboutPanel {
    @MainActor static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.labelColor
        ]
        let credits = NSMutableAttributedString(string: "Created by\n", attributes: base)
        var author = base
        author[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold)
        credits.append(NSAttributedString(string: "Justin Hourigan\n\n", attributes: author))
        var support = base
        support[.link] = URL(string: "https://buymeacoffee.com/justhour")!
        support[.foregroundColor] = NSColor.linkColor
        support[.underlineStyle] = NSUnderlineStyle.single.rawValue
        credits.append(NSAttributedString(string: "Buy Me a Coffee", attributes: support))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "STL Medic", .credits: credits])
    }
}
