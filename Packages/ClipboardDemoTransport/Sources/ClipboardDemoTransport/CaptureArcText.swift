import Foundation

/// Shared translations for the Mac receiver and iPhone app/extension.
public enum CaptureArcText {
    private static let translations: Bundle = {
        // SwiftPM command-line packages use Bundle.main.bundleURL. A packaged
        // macOS app puts resources in Contents/Resources instead.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ClipboardDemoTransport_ClipboardDemoTransport.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()
    public static func value(_ key: String) -> String {
        NSLocalizedString(key, bundle: translations, comment: "")
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: value(key), locale: Locale.current, arguments: arguments)
    }
}
