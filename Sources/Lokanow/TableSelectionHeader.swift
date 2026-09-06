import SwiftUI
import AppKit

/// A native three-state checkbox over the table's reserved selection-column header.
/// Its presence does not depend on SwiftUI's private AppKit view hierarchy.
struct TableSelectionHeader: NSViewRepresentable {
    let selectedCount: Int
    let totalCount: Int
    let enabled: Bool
    let label: String
    let onChange: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle))
        button.controlSize = .small
        button.allowsMixedState = true
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.allSelected = totalCount > 0 && selectedCount == totalCount
        button.state = selectedCount == 0 ? .off : (selectedCount == totalCount ? .on : .mixed)
        button.isEnabled = enabled && totalCount > 0
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }
    final class Coordinator: NSObject {
        var allSelected = false
        var onChange: ((Bool) -> Void)?
        @objc func toggle() { onChange?(!allSelected) }
    }
}
