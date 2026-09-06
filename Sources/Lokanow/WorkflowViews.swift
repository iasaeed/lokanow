import SwiftUI
import AppKit
import LocalizeCore

struct TranslationsView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeading(eyebrow: "03 / Bring in your translations", title: "Translation Import", subtitle: "Find existing Lokalise translations using your exact English source values.")
                HStack(spacing: 14) { Metric(title: "Selected modules", value: "\(model.selected.count)", icon: "square.stack.3d.up"); Metric(title: "Target languages", value: "\(model.languageMap.count)", icon: "globe") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Label("Lokalise connection", systemImage: "link").font(.headline); Spacer(); SettingsLink { Text("Connection settings") } }
                        Text(model.defaultProject.isEmpty ? "Choose a project in Settings. Modules can override this mapping." : "Default project: \(model.defaultProject)\(model.defaultBranch.isEmpty ? "" : " · " + model.defaultBranch)").foregroundStyle(.secondary)
                        ForEach(model.selected) { module in
                            HStack { Text(module.name); Spacer(); Text(model.saved.options[module.id]?.remoteProject.isEmpty == false ? model.saved.options[module.id]!.remoteProject : "Uses default project").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(12)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Languages & matching").font(.headline)
                        HStack { TextField("English source locale", text: $model.sourceLocale).frame(width: 250); Spacer(); Button("Load available languages") { model.loadLanguages() }.disabled(model.defaultProject.isEmpty) }
                        if model.languages.isEmpty { Text("Arabic is selected by default. Connect in Settings to select Hindi or other available languages.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(model.languages.filter { $0.lang_iso != model.sourceLocale }) { language in
                            HStack {
                                Toggle("\(language.lang_name) (\(language.lang_iso))", isOn: Binding(get: { model.languageMap[language.lang_iso] != nil }, set: { if $0 { model.languageMap[language.lang_iso] = LanguageMapping.appleLocale(for: language.lang_iso) } else { model.languageMap.removeValue(forKey: language.lang_iso) } }))
                                Spacer()
                                if model.languageMap[language.lang_iso] != nil { TextField("Apple locale", text: Binding(get: { model.languageMap[language.lang_iso] ?? "" }, set: { model.languageMap[language.lang_iso] = $0 })).frame(width: 110) }
                            }
                        }
                        HStack { Text("Selected: " + model.languageMap.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary); Spacer(); if !model.languages.isEmpty { Button("Select all target languages") { for language in model.languages where language.lang_iso != model.sourceLocale { model.languageMap[language.lang_iso] = LanguageMapping.appleLocale(for: language.lang_iso) } } } }
                        Divider()
                        Toggle("Import reviewed translations only", isOn: $model.requireReviewed)
                        Toggle("Replace differing local translations in the preview", isOn: $model.replaceExisting)
                        Text("Existing values are preserved unless replacement is selected. Fuzzy matches are never applied automatically.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Use local translation cache (offline lookup)", isOn: $model.useCache)
                        if let date = model.cacheDate { Text("Cached \(date.formatted(date: .abbreviated, time: .shortened)) · Automatically refreshed on launch").font(.caption).foregroundStyle(.secondary) }
                    }.padding(12)
                }
                HStack { Text("Only your local files are updated. Lokalise is read-only.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Find & Preview Translations") { model.previewImport() }.buttonStyle(.bordered).controlSize(.small).disabled(model.selected.isEmpty || model.languageMap.isEmpty || model.recoveryNeeded || model.cacheRefreshing) }
            }.padding(12)
        }.disabled(model.busy)
    }
}
struct PlanView: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    let plan: ChangePlan
    @State var selected: String?
    @State var mode = "Diff"
    var current: FileChange? { plan.changes.first { $0.id == selected } ?? plan.changes.first }
    @State private var previewPages: [String] = []
    @State private var previewPage = 0
    @State private var previewLoading = true
    @State private var loadedPreviewID: String?
    @State private var cachedFileID: String?
    @State private var cachedPreviews: [String: [String]] = [:]
    @State private var previewError: String?
    private var previewID: String { (current?.id ?? "") + ":" + mode }
    private func loadPreview() async {
        guard !Task.isCancelled, let change = current else { return }
        let requestID = previewID, requestedMode = mode
        if cachedFileID != change.id { cachedPreviews = [:]; cachedFileID = change.id }
        previewPage = 0; previewError = nil
        if let pages = cachedPreviews[requestedMode] {
            previewPages = pages; loadedPreviewID = requestID; previewLoading = false
            return
        }
        previewLoading = true; previewPages = []
        let work = Task.detached(priority: .userInitiated) { try FilePreview.pages(change, mode: requestedMode) }
        do {
            let pages = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            guard previewID == requestID else { return }
            cachedPreviews[requestedMode] = pages
            previewPages = pages; loadedPreviewID = requestID; previewLoading = false
        } catch {
            guard !Task.isCancelled, previewID == requestID else { return }
            previewError = error.localizedDescription; loadedPreviewID = requestID; previewLoading = false
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text(plan.title).font(.system(size: 13, weight: .semibold)); Text("\(plan.changes.count) files · \(plan.rows.count) results · No changes applied yet").foregroundStyle(.secondary) }; Spacer(); if model.busy { ProgressView() } }
            HSplitView {
                List(plan.changes, selection: $selected) { change in VStack(alignment: .leading, spacing: 4) { Text(change.url.lastPathComponent).font(.subheadline.weight(.medium)); Text(relativePath(change.url, root: plan.root)).font(.caption2).foregroundStyle(.secondary); Text(change.reason).font(.caption2).foregroundStyle(.secondary) }.padding(.vertical, 5).tag(change.id) }.frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                VStack(alignment: .leading, spacing: 12) {
                    if let current {
                        HStack { Text(current.before == nil ? "New file" : "File preview").font(.headline); Spacer(); Picker("Version", selection: $mode) { Text("Diff").tag("Diff"); Text("After").tag("After"); Text("Before").tag("Before") }.pickerStyle(.segmented).frame(width: 230) }
                        if previewLoading || loadedPreviewID != previewID {
                            VStack(spacing: 10) { ProgressView(); Text("Preparing file preview…").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let previewError {
                            ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle", description: Text(previewError))
                        } else {
                            if previewPages.indices.contains(previewPage), !previewPages[previewPage].isEmpty {
                                NativeFilePreview(text: previewPages[previewPage], isDiff: mode == "Diff")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ContentUnavailableView("Empty file", systemImage: "doc", description: Text("This version contains no text."))
                            }
                            if previewPages.count > 1 {
                                HStack {
                                    Button("Previous") { previewPage -= 1 }.disabled(previewPage == 0)
                                    Text("Page \(previewPage + 1) of \(previewPages.count)").monospacedDigit()
                                    Button("Next") { previewPage += 1 }.disabled(previewPage + 1 >= previewPages.count)
                                    Spacer()
                                    Text("Full file will be applied.").foregroundStyle(.secondary)
                                }.font(.caption)
                            }
                        }
                    }
                }.padding(.leading, 12).frame(minWidth: 600)
            }
            if plan.rows.contains(where: \.unresolved) { Label("\(plan.rows.filter(\.unresolved).count) unresolved results will be included in the report.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            HStack { Text("Backups are saved in your project’s .lokanow folder.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Apply \(plan.changes.count) File Changes") { model.applyPlan() }.buttonStyle(.bordered).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 1050, idealWidth: 1180, minHeight: 560, idealHeight: 720).disabled(model.busy).interactiveDismissDisabled(model.busy)
        .task(id: previewID) { await loadPreview() }
    }
}
/// AppKit lays out selectable text inside a constrained scroll view, without SwiftUI Text sizing.
private struct NativeFilePreview: NSViewRepresentable {
    let text: String
    let isDiff: Bool
    final class Coordinator {
        var text: String?
        var isDiff = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = NSTextView(frame: .zero)
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.backgroundColor = .textBackgroundColor
        editor.setAccessibilityLabel("File preview")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView,
              context.coordinator.text != text || context.coordinator.isDiff != isDiff else { return }
        context.coordinator.text = text; context.coordinator.isDiff = isDiff
        editor.textStorage?.setAttributedString(FilePreview.attributedPage(text, isDiff: isDiff))
        editor.scrollToBeginningOfDocument(nil)
    }
}

struct ReportsView: View {
    @EnvironmentObject var model: StudioModel
    @State var reportID: UUID?
    @State var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\ReportRow.english)]
    @State var unresolvedOnly = false
    @State var query = ""
    var report: OperationReport? { model.reports.first { $0.id == reportID } ?? model.reports.first }
    var rows: [ReportRow] { (report?.rows ?? []).filter { (!unresolvedOnly || $0.unresolved) && (query.isEmpty || $0.english.localizedCaseInsensitiveContains(query) || $0.key.localizedCaseInsensitiveContains(query) || $0.status.localizedCaseInsensitiveContains(query)) } }
    var current: ReportRow? { rows.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeading(eyebrow: "04 / Close the loop", title: "Operation Reports", subtitle: "Share unresolved English values with your content team, or inspect exactly what changed.")
            if model.reports.isEmpty { ContentUnavailableView("No reports yet", systemImage: "doc.text", description: Text("Register strings, import translations, or export an analysis to create a report.")) }
            else {
                HStack {
                    Picker("Operation", selection: $reportID) { ForEach(model.reports) { report in Text("\(report.title) · \(report.date.formatted(date: .abbreviated, time: .shortened))").tag(Optional(report.id)) } }.frame(maxWidth: 470)
                    Spacer(); Button("Undo last file operation") { model.undo() }.disabled(model.busy)
                }
                HStack { TextField("Search report", text: $query).textFieldStyle(.roundedBorder); Toggle("Unresolved only", isOn: $unresolvedOnly).toggleStyle(.checkbox) }
                Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("English", value: \.english).width(min: 150, ideal: 260)
                    TableColumn("Key", value: \.key) { Text($0.key).font(.system(.caption, design: .monospaced)) }.width(min: 150, ideal: 230)
                    TableColumn("Language", value: \.language).width(70)
                    TableColumn("Status", value: \.status) { StatusBadge(status: $0.status) }.width(100)
                    TableColumn("Reason", value: \.reason).width(min: 180, ideal: 260)
                }
                if let current {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(current.english).font(.headline).textSelection(.enabled)
                        Text(current.reason).font(.caption).foregroundStyle(.secondary)
                        if !current.source.isEmpty { Text(current.source).font(.caption).textSelection(.enabled) }
                        if current.status == "Ambiguous" { MatchChooser(row: current) }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor))
                }
                HStack {
                    Text("\(rows.count) results · \(Set(rows.map { $0.module + ":" + $0.key }).count) unique messages").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Copy selected") { if let current { model.copy([current]) } }.disabled(current == nil)
                    Button("Copy unresolved") { model.copy((report?.rows ?? []).filter(\.unresolved)) }
                    Menu("Export") { Button("CSV") { model.export(rows, format: "csv") }; Button("JSON") { model.export(rows, format: "json") }; Button("Markdown") { model.export(rows, format: "md") } }
                }
            }
        }.padding(12).onAppear { reportID = model.reports.first?.id }
    }
}
struct MatchChooser: View {
    @EnvironmentObject var model: StudioModel
    let row: ReportRow
    var module: Module? { model.modules.first { $0.name == row.module } }
    var candidates: [RemoteKey] { guard let module else { return [] }; return TranslationIndex(keys: model.matchingKeys[module.id] ?? [], englishLocale: model.sourceLocale).match(row.english).candidates }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(candidates) { key in
                HStack {
                    VStack(alignment: .leading) { Text("#\(key.id) · \(key.key_name["ios"] ?? key.key_name.values.sorted().first ?? "Unnamed key")").font(.caption.bold()); Text(key.description ?? "No description").font(.caption).foregroundStyle(.secondary); Text(key.translations.filter { model.languageMap[$0.language_iso] != nil }.map { "\($0.language_iso): \($0.translation)" }.joined(separator: " · ")).font(.caption).textSelection(.enabled) }
                    Spacer()
                    Button("Use this key") {
                        guard let module, key.translations.contains(where: { $0.language_iso == model.sourceLocale && $0.translation == row.english }) else { model.error = "The English text differs. Correct the source in Lokalise or locally before matching."; return }
                        model.saved.remoteMappings[stableID(module.id + ":" + row.key + ":" + row.english)] = key.id; model.persist(); model.notice = "Mapping saved. Run Find & Preview Translations again to apply it."
                    }
                }
            }
            if candidates.isEmpty { Text("Run translation lookup again to load candidate details.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup("Lokalise connection") {
                        SettingsField("API token") { SecureField("API token", text: $model.token).labelsHidden().disabled(model.cacheRefreshing) }
                        helpText("Use a token with read access to projects, keys, languages, and translations. Stored in macOS Keychain.")
                        HStack {
                            Button("Save & Test Connection") { model.testConnection() }.disabled(model.busy || model.cacheRefreshing || model.token.isEmpty)
                            Button("Disconnect") { model.disconnect() }.disabled(model.busy || model.cacheRefreshing)
                            if model.connected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                        if model.busy { ProgressView(model.activity) }
                    }
                    SettingsGroup("Default project") {
                        if !model.projects.isEmpty {
                            SettingsField("Project") { Picker("Project", selection: $model.defaultProject) { Text("Select project").tag(""); ForEach(model.projects) { Text($0.name).tag($0.id) } }.labelsHidden() }
                        }
                        SettingsField("Project ID") { TextField("Project ID", text: $model.defaultProject).labelsHidden() }
                        HStack(alignment: .top, spacing: 16) {
                            SettingsField("Branch (optional)") { TextField("Branch", text: $model.defaultBranch).labelsHidden() }
                            SettingsField("Source locale") { TextField("Source locale", text: $model.sourceLocale).labelsHidden() }.frame(width: 130)
                        }
                        helpText("Module overrides are available in Modules → Configure.")
                    }
                    SettingsGroup("Translation cache") {
                        helpText("All accessible projects and configured branches refresh on launch. Every key and available language is stored locally. Failed downloads preserve the previous snapshot.")
                        HStack {
                            Button("Refresh Now") { model.refreshTranslationCache() }.disabled(model.cacheRefreshing || model.token.isEmpty || model.busy)
                            if model.cacheRefreshing { ProgressView().controlSize(.small); Button("Cancel Refresh") { model.cancelCacheRefresh() } }
                            Spacer()
                            Button("Clear Cache") { model.clearCache() }.disabled(model.cacheRefreshing || model.busy)
                        }
                    }
                    SettingsGroup("Privacy") {
                        helpText("Source analysis stays on your Mac. Lokalise access is read-only. Lokanow has no telemetry or automatic source uploads.")
                    }
                    HStack { Spacer(); Button("Save Settings") { model.saveSettings() }.disabled(model.cacheRefreshing || model.busy) }
                    if let notice = model.notice { helpText(notice) }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.tabItem { Label("Connection", systemImage: "key") }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup("Project analysis rules") {
                        SettingsField("Excluded folders") { TextField("For example: Vendor, Generated", text: $model.saved.exclusions).labelsHidden().accessibilityLabel("Additional excluded folder names") }
                        helpText("Additional folder names to skip, separated by commas.")
                        SettingsField("Localization wrappers") { TextField("For example: localize, L10n.text", text: $model.saved.wrappers).labelsHidden().accessibilityLabel("Localization wrapper names") }
                        helpText("Separate wrapper names with commas. Custom wrappers are flagged for review; their table and bundle contracts are never guessed.")
                        Divider().padding(.vertical, 4)
                        Text("\(model.saved.excludedFindings.count) individual findings excluded.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Reset Excluded Findings") { model.saved.excludedFindings = []; model.persist() }.disabled(model.root == nil || model.busy)
                            Spacer()
                            Button("Save Rules") { model.persist(); model.analysis = nil; model.findings = []; model.discover() }.disabled(model.busy || model.root == nil)
                        }
                        if model.root == nil { helpText("Open a project to edit and save its analysis rules.") }
                    }
                    SettingsGroup("About") {
                        Text("Lokanow 1.0").font(.system(size: 13, weight: .semibold))
                        helpText("Native macOS localization workspace. macOS 14 or later. Built with SwiftUI and SwiftSyntax.")
                        helpText("Interpolation, plural conversion, custom wrapper rewriting, and uncertain bundle ownership require manual review. Existing content is preserved.")
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.tabItem { Label("Analysis", systemImage: "slider.horizontal.3") }
        }.font(.system(size: 13)).controlSize(.small).textFieldStyle(.roundedBorder).frame(width: 680, height: 620)
    }
    private func helpText(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Divider()
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12))
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
