import AppKit
import Observation

/// A newer GitHub release, noticed but never installed. The app only opens the release page;
/// the disk image is downloaded and installed by hand.
@MainActor @Observable
final class ReleaseNotice {
    struct Release: Equatable {
        var version: String
        var page: URL
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
        return Release(version: version, page: page)
    }
}

private struct GitHubRelease: Decodable {
    var tag_name: String
    var html_url: String
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
