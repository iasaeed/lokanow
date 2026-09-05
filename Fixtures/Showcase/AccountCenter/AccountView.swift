import SwiftUI
final class LocalizationBundleToken: NSObject {}
public struct AccountView: View {
    public init() {}
    let name = "Developer"
    public var body: some View {
        VStack {
            Text("How to Open an account")
            Button("Continue") {}
            Label("Your documents", systemImage: "doc")
            Text("Hello \(name)")
            Text(verbatim: "QA-only")
            Image(systemName: "building.columns")
        }
    }
}
