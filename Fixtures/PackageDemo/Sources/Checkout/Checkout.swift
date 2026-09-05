import SwiftUI
public struct CheckoutView: View {
    public init() {}
    public var body: some View { Text("Confirm order") }
}
public enum CheckoutLocalization {
    public static func value(_ key: String, locale: String) -> String {
        guard let path = Bundle.module.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return "Unavailable" }
        return bundle.localizedString(forKey: key, value: "English fallback", table: "Localizable")
    }
}
