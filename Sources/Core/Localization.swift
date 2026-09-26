import Foundation

/// SpaceLens ships two languages.
///
/// The host app writes the choice into its own preference domain. The Quick Look extension runs in a
/// separate sandbox and reads the same domain through a read-only shared-preference exception, so
/// the preview window follows the setting as well. When nothing is stored, the system language
/// decides.
public enum SpaceLensLanguage: String, CaseIterable, Sendable {
    case system
    case chinese = "zh"
    case english = "en"
}

/// Shared lookup helper for the host app, the Quick Look extension and the core preview loaders.
///
/// Both translations live next to each other at the call site instead of in a resource keyed table,
/// so a missing translation shows up while reading the code and no key can drift out of sync.
public enum L10n {
    /// Preference domain shared by the app and its extension.
    public static let preferenceDomain = "io.github.linzh0632.SpaceLens"
    public static let languageKey = "language"

    private static let sharedDefaults = UserDefaults(suiteName: preferenceDomain)
    /// Test override, so assertions never depend on the machine running them.
    private static let pin = LanguagePin()

    /// Forces a language for the current process; pass `nil` to resolve normally again.
    public static func pinForTesting(_ language: SpaceLensLanguage?) {
        pin.language = language
    }

    /// The language in effect for this process.
    public static var language: SpaceLensLanguage {
        if let pinned = pin.language { return resolved(pinned) }
        if let raw = storedValue(), let stored = SpaceLensLanguage(rawValue: raw) {
            return resolved(stored)
        }
        return systemLanguage
    }

    /// The app writes the choice into its own domain, so it reads that domain first. The sandboxed
    /// extension has nothing in its own domain and reaches the app's domain through the
    /// shared-preference suite granted by its entitlements.
    private static func storedValue() -> String? {
        if let raw = UserDefaults.standard.string(forKey: languageKey) { return raw }
        return sharedDefaults?.string(forKey: languageKey)
    }

    public static var isEnglish: Bool { language == .english }

    /// Locale for number, byte and date formatting, so formatted values follow the chosen language
    /// instead of the system one.
    public static var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "zh_Hans_CN")
    }

    /// Counts a noun: English needs a plural form, Chinese uses one wording.
    public static func count<T: BinaryInteger>(_ value: T, _ chineseUnit: String,
                                               _ singular: String, _ plural: String) -> String {
        "\(value) \(isEnglish ? (value == 1 ? singular : plural) : chineseUnit)"
    }

    /// Picks between the Chinese and the English wording.
    public static func text(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }

    private static func resolved(_ language: SpaceLensLanguage) -> SpaceLensLanguage {
        language == .system ? systemLanguage : language
    }

    private static var systemLanguage: SpaceLensLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .chinese : .english
    }
}

/// Lock-protected storage that keeps the shared helper free of global mutable state.
private final class LanguagePin: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SpaceLensLanguage?

    var language: SpaceLensLanguage? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
