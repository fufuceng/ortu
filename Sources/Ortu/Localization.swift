import Foundation

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, bundle: .module, locale: .current, arguments: arguments)
    }

    static func text(_ key: String, localeIdentifier: String, _ arguments: CVarArg...) -> String {
        let languageCode = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier
        let localizedBundle =
            Bundle.module.path(forResource: languageCode, ofType: "lproj")
            .flatMap(Bundle.init(path:))
            ?? .module
        return text(
            key,
            bundle: localizedBundle,
            locale: Locale(identifier: localeIdentifier),
            arguments: arguments
        )
    }

    private static func text(
        _ key: String,
        bundle: Bundle,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }
}
