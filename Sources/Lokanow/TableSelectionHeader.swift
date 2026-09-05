import SwiftUI
import AppKit

/// SwiftUI's macOS Table accepts text-only column titles. Install a native checkbox
/// in the empty selection-column header while preserving native sorting headers.
struct TableSelectionHeader: NSViewRepresentable {
    let selectedCount: Int
    let totalCount: Int
    let enabled: Bool
    let label: String
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.allSelected = totalCount > 0 && selectedCount == totalCount
        coordinator.button.state = selectedCount == 0 ? .off : (selectedCount == totalCount ? .on : .mixed)
        coordinator.button.isEnabled = enabled && totalCount > 0
        coordinator.button.setAccessibilityLabel(label)
        coordinator.button.toolTip = label
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            var ancestor = view.superview
            while let container = ancestor {
                if let table = Self.findTable(in: container), let header = table.headerView,
                   let column = table.tableColumns.firstIndex(where: { $0.title.isEmpty }) {
                    coordinator.attach(to: header, table: table, column: column)
                    return
                }
                ancestor = container.superview
            }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }
    private static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let table = findTable(in: child) { return table } }
        return nil
    }
    final class Coordinator: NSObject {
        let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        var onChange: ((Bool) -> Void)?
        var allSelected = false
        private var observer: NSObjectProtocol?
        override init() {
            super.init()
            button.controlSize = .small
            button.allowsMixedState = true
            button.target = self
            button.action = #selector(toggle)
        }
        @objc private func toggle() { onChange?(!allSelected) }
        func attach(to header: NSTableHeaderView, table: NSTableView, column: Int) {
            if button.superview !== header {
                detach()
                header.addSubview(button)
                header.postsFrameChangedNotifications = true
                observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: header, queue: .main) { [weak self, weak header] _ in
                    guard let self, let header else { return }
                    self.position(in: header, column: column)
                }
            }
            position(in: header, column: column)
        }
        private func position(in header: NSTableHeaderView, column: Int) {
            let rect = header.headerRect(ofColumn: column)
            button.frame = NSRect(x: rect.midX - 9, y: rect.midY - 9, width: 18, height: 18)
        }
        func detach() {
            button.removeFromSuperview()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
