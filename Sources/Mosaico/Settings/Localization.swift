import Foundation

/// UI language. `system` follows macOS (including the per-app language set
/// in System Settings → General → Language & Region → Applications).
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case italian = "it"

    var id: String { rawValue }

    /// Shown in the language's own name, as macOS does.
    var nativeName: String {
        switch self {
        case .system: return tr("System default")
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }
}

/// UI strings: English is the source language and the key; translations
/// live in Resources/<lang>.lproj/Localizable.strings.
///
/// Looked up by hand instead of through Bundle.main so the language can be
/// switched from Settings without a restart, and so `swift run` finds the
/// tables in the source tree (a bare executable has no Resources).
enum Localization {
    static let supported = ["en", "it"]

    private static var tables: [String: [String: String]] = [:]

    /// Language currently shown.
    static var current: String {
        let chosen = SettingsStore.shared.settings.language
        if chosen != .system { return chosen.rawValue }
        // Explicit preferences: without them the call answers with the
        // development region ("en") even on an Italian system
        return Bundle.preferredLocalizations(from: supported,
                                             forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    static func string(_ key: String, language: String = current) -> String {
        guard language != "en" else { return key }
        return table(for: language)[key] ?? key
    }

    static func table(for language: String) -> [String: String] {
        if let cached = tables[language] { return cached }
        let table = tableURL(for: language)
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        tables[language] = table
        return table
    }

    private static func tableURL(for language: String) -> URL? {
        let name = "\(language).lproj/Localizable.strings"
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        // Development run from the build directory: Sources/Mosaico/Settings → repo root
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = repo.appendingPathComponent("Resources").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
}

/// Translated UI string; extra arguments fill its format specifiers.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = Localization.string(key)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
