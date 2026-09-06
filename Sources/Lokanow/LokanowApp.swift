import SwiftUI

@main struct LokanowApp: App {
    @StateObject private var model = StudioModel()
    var body: some Scene {
        WindowGroup("Lokanow") {
            StudioView().environmentObject(model).frame(minWidth: 1080, minHeight: 560).task { await model.start() }
        }
        .defaultSize(width: 1380, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open Project…") { model.chooseProject() }.keyboardShortcut("o").disabled(model.busy) }
            CommandMenu("Localization") {
                Button("Analyze Selected Modules") { model.analyze() }.keyboardShortcut("r").disabled(model.busy || model.selected.isEmpty)
                Button("Preview Registration") { model.previewRegistration() }.keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(model.busy || model.readyCount == 0)
                Button("Undo Last File Operation") { model.undo() }.disabled(model.busy || model.root == nil)
            }
        }
        Settings { SettingsView().environmentObject(model) }
    }
}
