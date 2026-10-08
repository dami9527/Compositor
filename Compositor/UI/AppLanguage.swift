import AppKit

/// Which language the interface uses. The wording lives in `Localizable.xcstrings`,
/// one language beside another, so adding a language means filling in that catalog.
/// A file the user drops in later can't supply menu titles: the app is sandboxed,
/// and those titles have to be inside the bundle.
@MainActor
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    private static let choiceKey = "compositor.language"
    /// Set only while a language change is quitting the app. A cancelled save clears it, so quitting later doesn't relaunch.
    static var pending: AppLanguage?
    private static var savedChoice: String?
    private static var savedAppleLanguages: Any?

    /// The language this process actually launched with.
    static var current: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return code.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static func choose(_ language: AppLanguage) {
        guard language != current else { return }
        let alert = NSAlert()
        alert.messageText = "Relaunch to change the language?".localized
        alert.informativeText = "Compositor will quit and open again. Save the open project when asked.".localized
        alert.addButton(withTitle: "Relaunch".localized)
        alert.addButton(withTitle: "Cancel".localized)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        savedChoice = UserDefaults.standard.string(forKey: choiceKey)
        savedAppleLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        UserDefaults.standard.set(language.rawValue, forKey: choiceKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        pending = language
        NSApp.terminate(nil)
    }

    static func cancelPendingRelaunch() {
        guard pending != nil else { return }
        pending = nil
        if let savedChoice {
            UserDefaults.standard.set(savedChoice, forKey: choiceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: choiceKey)
        }
        if let savedAppleLanguages {
            UserDefaults.standard.set(savedAppleLanguages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Opens a second copy, which reads the language saved just before quitting.
    static func relaunchIfNeeded() {
        guard pending != nil else { return }
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        let group = DispatchGroup()
        group.enter()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in group.leave() }
        let deadline = Date().addingTimeInterval(2)
        while group.wait(timeout: .now()) == .timedOut, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

extension String {
    /// The catalog entry for this English source text, or the text itself when that entry is missing.
    /// Nonisolated: names are built while pixels are worked on, off the main actor, as well as in views.
    nonisolated var localized: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }

    /// Undo names stay English in the history. Exact catalog keys translate, and a few built names
    /// carry a filter or effect title in the middle.
    nonisolated var localizedAction: String {
        let direct = localized
        if direct != self { return direct }
        let wrapped = [
            ("New ", " Adjustment", "New %@ Adjustment"),
            ("Edit ", " Adjustment", "Edit %@ Adjustment")
        ]
        for (prefix, suffix, format) in wrapped {
            if hasPrefix(prefix), hasSuffix(suffix), count > prefix.count + suffix.count {
                let kind = String(dropFirst(prefix.count).dropLast(suffix.count))
                return String(format: format.localized, kind.localized)
            }
        }
        for prefix in ["Cancel ", "Edit ", "Add ", "Copy ", "Hide ", "Show ", "Remove "] {
            if hasPrefix(prefix), count > prefix.count {
                let format = prefix.trimmingCharacters(in: .whitespaces) + " %@"
                return String(format: format.localized, String(dropFirst(prefix.count)).localized)
            }
        }
        return self
    }
}
