import SwiftUI
import AccountCenter
@main struct DemoApp: App {
    var body: some Scene {
        WindowGroup { NavigationStack { AccountView().navigationTitle("Welcome home") } }
    }
}
