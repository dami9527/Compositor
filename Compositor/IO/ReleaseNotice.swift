import AppKit
import Observation

/// A newer GitHub release, noticed but never installed. The app only opens the release page;
/// the disk image is downloaded and installed by hand.
@MainActor @Observable
final class ReleaseNotice {
    struct Release: Equatable {
        var version: String
        var page: URL
        /// The release notes' own bullet lines: what the details alert lists.
        var changes: [String] = []
    }

    private(set) var available: Release?
    private(set) var dismissedVersion: String?
    @ObservationIgnored private var lastCheck: Date?
    private static let repo = "dami9527/Compositor"
    private static let dismissedKey = "compositor.updateNotice.dismissedVersion"
    private static let gap: TimeInterval = 4 * 60 * 60

    init() {
        dismissedVersion = UserDefaults.standard.string(forKey: Self.dismissedKey)
    }

    /// Shown until this version is dismissed. A later release shows the bar again.
    var banner: Release? {
        guard let available, dismissedVersion != available.version else { return nil }
        return available
    }

    func checkIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.gap { return }
        lastCheck = Date()
        Task { await check() }
    }

    func open() {
        guard let available else { return }
        NSWorkspace.shared.open(available.page)
    }

    /// What's in the new version, in an alert of its own, with the download page one button away. Built in AppKit so
    /// the menu can show it too, where there may be no window to hang a sheet on.
    func showDetails() {
        guard let available else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(format: "Version %@ is available".localized, available.version)
        alert.informativeText = String(format: "You have %@.".localized, Self.installedVersion)
        if !available.changes.isEmpty { alert.accessoryView = Self.changesView(available.changes) }
        alert.addButton(withTitle: "Download".localized)
        alert.addButton(withTitle: "Later".localized)
        alert.layout()
        // Download, the default button, leaves for the release page; Later only closes the alert.
        if alert.runModal() == .alertFirstButtonReturn { open() }
    }

    func dismiss() {
        guard let available else { return }
        dismissedVersion = available.version
        UserDefaults.standard.set(available.version, forKey: Self.dismissedKey)
    }

    private func check() async {
        do {
            guard let latest = try await Self.latest(),
                  let current = Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
                  let remote = Version(latest.version),
                  current < remote else {
                available = nil
                return
            }
            available = latest
        } catch {
            // Offline, or no release published yet. Try again the next time the app is brought forward.
            lastCheck = nil
        }
    }

    private static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func latest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("Compositor", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        // Nothing has been published. That is not a failure to retry.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = Version(decoded.tag_name)?.description,
              let page = URL(string: decoded.html_url),
              page.scheme == "https", page.host == "github.com",
              page.path.hasPrefix("/\(repo)/") else { return nil }
        return Release(version: version, page: page, changes: changes(in: decoded.body ?? ""))
    }

    /// The notes' bullet lines. The paragraph above them, the `---` rule and the install footer below are all left
    /// out: the alert wants the changes themselves, a line each, without the markdown dash.
    private static func changes(in body: String) -> [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("• ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// What's new, as a wrapped list under the alert's message: a bullet a line, and a scrollbar once the release
    /// has more to say than the alert should grow to. 420 wide is the alert's own text column at this width, so
    /// nothing is clipped.
    private static func changesView(_ changes: [String]) -> NSView {
        let style = NSMutableParagraphStyle()
        style.headIndent = 12
        style.paragraphSpacing = 4
        style.tabStops = [NSTextTab(textAlignment: .left, location: 12)]
        let text = NSMutableAttributedString(string: "What’s new".localized + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: style,
        ])
        text.append(NSAttributedString(string: changes.map { "•\t\($0)" }.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style,
        ]))
        let width: CGFloat = 420
        // A text view rather than a label: it wraps to this width, reports the height it needs, and is flipped, so
        // a list too long for the alert starts at its first line rather than its last.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textStorage?.setAttributedString(text)
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return textView }
        layout.ensureLayout(for: container)
        let contentHeight = ceil(layout.usedRect(for: container).height)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        let height = min(contentHeight, Self.changesHeightCap)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = contentHeight > height + 0.5
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    /// The tallest the list grows before it scrolls instead, so the alert stays a dialog rather than a page.
    private static let changesHeightCap: CGFloat = 260
}

private struct GitHubRelease: Decodable {
    var tag_name: String
    var html_url: String
    var body: String?
}

/// `1.4.10` is newer than `1.4.5`. A leading `v` is ignored, and missing pieces count as zero.
private struct Version: Comparable, CustomStringConvertible {
    var parts: [Int]
    var description: String { parts.map(String.init).joined(separator: ".") }

    init?(_ string: String) {
        var text = string
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
