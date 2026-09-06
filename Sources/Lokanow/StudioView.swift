import SwiftUI
import AppKit
import LocalizeCore

// Native semantic colors follow macOS light, dark, and accessibility appearances.
struct StudioView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Navigator", selection: $model.page) {
                    ForEach(StudioModel.Page.allCases) { page in
                        Image(systemName: page.icon).help(page.rawValue).tag(page)
                    }
                }.pickerStyle(.segmented).labelsHidden().padding(8)
                Divider()
                List(selection: $model.page) {
                    Section(model.root?.lastPathComponent ?? "Workspace") {
                        ForEach(StudioModel.Page.allCases) { page in
                            Label(page.rawValue, systemImage: page.icon).tag(page)
                        }
                    }
                    if !model.selected.isEmpty {
                        Section("Selected Targets") {
                            ForEach(model.selected) { module in
                                Label(module.name, systemImage: module.kind == "Application" ? "app" : "shippingbox")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                HStack {
                    Button { model.chooseProject() } label: { Image(systemName: "folder.badge.plus") }.help("Open Project…").disabled(model.busy)
                    Spacer()
                    Text("\(model.selected.count) selected").foregroundStyle(.secondary)
                }.buttonStyle(.borderless).padding(8)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.root?.path ?? "Workspace").lineLimit(1).truncationMode(.middle).help(model.root?.path ?? "Workspace")
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Label(model.page.rawValue, systemImage: model.page.icon)
                    Spacer()
                }.font(.system(size: 11)).padding(.horizontal, 12).frame(height: 29)
                Divider()
                if model.cacheRefreshing || model.cacheMessage != nil {
                    TranslationCacheView()
                    Divider()
                }
                if model.root == nil { WelcomeView() }
                else {
                    if model.recoveryNeeded { HStack { Label("An interrupted operation needs recovery.", systemImage: "exclamationmark.triangle"); Spacer(); Button("Restore backups") { model.recover() } }.padding(8).background(.orange.opacity(0.12)) }
                    switch model.page {
                    case .modules: ModulesView()
                    case .strings: StringsView()
                    case .translations: TranslationsView()
                    case .reports: ReportsView()
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    if model.busy {
                        ProgressView().controlSize(.mini)
                        Text(model.activity)
                        Spacer()
                        Button("Cancel") { model.cancel() }.disabled(model.activity.hasPrefix("Applying") || model.activity.hasPrefix("Restoring") || model.activity.hasPrefix("Recovering"))
                    } else {
                        Text(model.notice ?? "Ready").lineLimit(1).help(model.notice ?? "Ready")
                        Spacer()
                        Text("Swift").foregroundStyle(.secondary)
                        Divider().frame(height: 12)
                        Text("UTF-8").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 25)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(model.root?.lastPathComponent ?? "Lokanow")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
                        .disabled(!model.busy || model.activity.hasPrefix("Applying") || model.activity.hasPrefix("Restoring") || model.activity.hasPrefix("Recovering"))
                    Button { model.analyze() } label: { Label("Analyze Selected Modules", systemImage: "play.fill") }
                        .disabled(model.busy || model.selected.isEmpty || model.recoveryNeeded).help("Analyze Selected Modules (⌘R)")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Menu {
                            if let root = model.root { Text(root.path); Divider() }
                            Button("Change Project…") { model.chooseProject() }.disabled(model.busy)
                            Button("Close Project") { model.closeProject() }.disabled(model.busy || model.root == nil)
                        } label: {
                            Label(model.root?.lastPathComponent ?? "Open Project", systemImage: "folder")
                        }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize().labelStyle(.titleAndIcon).help(model.root?.path ?? "Choose a project folder")
                        Text(model.root?.deletingLastPathComponent().path ?? "Choose a folder").lineLimit(1).truncationMode(.middle).help(model.root?.path ?? "Choose a folder").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(model.busy ? model.activity : "Localization").foregroundStyle(.secondary).lineLimit(1)
                    }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 26).frame(maxWidth: 560)
                }
                ToolbarItemGroup {
                    Button { model.discover() } label: { Label("Refresh modules", systemImage: "arrow.clockwise") }.disabled(model.busy || model.root == nil)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .font(.system(size: 13)).controlSize(.small)
        .sheet(item: $model.plan) { plan in PlanView(plan: plan).environmentObject(model) }
        .alert("Action needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct WelcomeView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.bubble").font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
            Text("Lokanow").font(.system(size: 26, weight: .semibold))
            Text("Open a project to begin localizing its targets.").foregroundStyle(.secondary)
            Button { model.chooseProject() } label: { Label("Open Project…", systemImage: "folder") }.keyboardShortcut("o")
            Text("Xcode Projects · Workspaces · Swift Packages").font(.system(size: 11)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct PageHeading: View {
    let eyebrow: String, title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct Metric: View {
    let title: String, value: String, icon: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
            Text(title).foregroundStyle(.secondary)
        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct ModuleTableRow: Identifiable {
    let module: Module
    let prefix: String
    let localization: String
    var id: String { module.id }
    var name: String { module.name }
    var kind: String { module.kind }
    var fileCount: Int { module.sources.count }
}
struct ModulesView: View {
    @EnvironmentObject var model: StudioModel
    @State var query = ""
    @State var configuration: Module?
    @State var showRemoved = false
    @State private var showWarnings = false
    @State private var sortOrder = [KeyPathComparator(\ModuleTableRow.name)]
    private var rows: [ModuleTableRow] {
        filtered.map { ModuleTableRow(module: $0, prefix: model.saved.options[$0.id]?.prefix ?? "", localization: model.saved.options[$0.id]?.resourcePath ?? "") }.sorted(using: sortOrder)
    }
    private var selectableIDs: Set<String> { Set(filtered.filter { !(model.saved.removedModules ?? []).contains($0.id) }.map(\.id)) }
    var filtered: [Module] { model.modules.filter { (showRemoved || !(model.saved.removedModules ?? []).contains($0.id)) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.root.path.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeading(eyebrow: "", title: "Targets", subtitle: "Select targets and configure their localization resources.")
            HStack { TextField("Filter targets", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320); Spacer(); Toggle("Show Removed", isOn: $showRemoved).toggleStyle(.checkbox); Button("Select All") { model.saved.selectedModules.formUnion(filtered.filter { !(model.saved.removedModules ?? []).contains($0.id) }.map(\.id)); model.persist() }; Button("Deselect All") { model.saved.selectedModules = []; model.persist() } }
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("") { row in
                    let module = row.module
                    Toggle("Select \(module.name)", isOn: Binding(get: { model.saved.selectedModules.contains(module.id) }, set: { if $0 { model.saved.selectedModules.insert(module.id) } else { model.saved.selectedModules.remove(module.id) }; model.persist() })).labelsHidden().toggleStyle(.checkbox).disabled((model.saved.removedModules ?? []).contains(module.id))
                }.width(28)
                TableColumn("Target", value: \.name) { row in
                    let module = row.module
                    Label(module.name, systemImage: module.kind == "Application" ? "app" : "shippingbox").lineLimit(1).truncationMode(.middle).help(module.name + "\n" + module.root.path)
                }.width(min: 140, ideal: 200)
                TableColumn("Type", value: \.kind).width(min: 90, ideal: 110)
                TableColumn("Prefix", value: \.prefix) { row in Text(row.prefix).font(.system(size: 11, design: .monospaced)) }.width(60)
                TableColumn("Swift Files", value: \.fileCount) { Text("\($0.fileCount)").monospacedDigit() }.width(65)
                TableColumn("Localization", value: \.localization) { row in
                    let path = row.localization
                    if path.isEmpty { Label("Not configured", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    else { Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.text").help(path) }
                }.width(min: 160, ideal: 210)
                TableColumn("Actions") { row in
                    let module = row.module
                    HStack {
                        if (model.saved.removedModules ?? []).contains(module.id) {
                            Button("Restore") { model.restoreModule(module.id) }
                        } else {
                            Button("Configure…") { configuration = module }
                            Button { model.removeModule(module.id) } label: { Image(systemName: "minus.circle") }.help("Remove \(module.name) from workspace")
                        }
                    }
                }.width(120)
            }.overlay(alignment: .topLeading, content: { TableSelectionHeader(
                selectedCount: selectableIDs.intersection(model.saved.selectedModules).count,
                totalCount: selectableIDs.count, enabled: !model.busy,
                label: "Select all filtered modules") { select in
                    if select { model.saved.selectedModules.formUnion(selectableIDs) }
                    else { model.saved.selectedModules.subtract(selectableIDs) }
                    model.persist()
                }.frame(width: 18, height: 22).padding(.leading, 5) })
                .frame(minHeight: 240, maxHeight: .infinity)
                .contextMenu { Button("Refresh Targets") { model.discover() } }
            if filtered.isEmpty { Text(query.isEmpty ? (model.modules.isEmpty ? "No targets discovered in this project." : "All modules are removed. Enable Show Removed to restore them.") : "No matching targets.").foregroundStyle(.secondary) }
            let warningModules = filtered.filter { !$0.warnings.isEmpty }
            if !warningModules.isEmpty {
                HStack {
                    Label("\(warningModules.reduce(0) { $0 + $1.warnings.count }) warnings in \(warningModules.count) targets", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.system(size: 11))
                    Spacer()
                    Button("Review Warnings…") { showWarnings = true }
                }
            }
            HStack {
                Text("\(model.modules.count) targets · \(model.selected.count) selected · \(model.selected.reduce(0) { $0 + $1.sources.count }) Swift files").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Analyze Selected Modules") { model.analyze() }.disabled(model.selected.isEmpty || model.busy || model.recoveryNeeded)
            }
        }.padding(12).disabled(model.busy)
        .sheet(isPresented: $showWarnings) { ModuleWarningsView(modules: filtered.filter { !$0.warnings.isEmpty }) }
        .sheet(item: $configuration) { module in ModuleSettingsView(module: module, initial: model.saved.options[module.id] ?? ModuleOptions(module: module)).environmentObject(model) }
    }
}
struct ModuleWarningsView: View {
    @Environment(\.dismiss) private var dismiss
    let modules: [Module]
    @State private var query = ""
    private var matching: [Module] {
        modules.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.warnings.contains { $0.localizedCaseInsensitiveContains(query) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Module Warnings").font(.headline)
            Text("Review discovery warnings before configuring the affected targets.").foregroundStyle(.secondary)
            TextField("Search targets or warnings", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(matching) { module in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(module.name).font(.system(size: 13, weight: .semibold))
                            Text(module.root.path).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(module.warnings.enumerated()), id: \.offset) { _, warning in
                                Label { Text(warning).textSelection(.enabled) } icon: {
                                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                    if matching.isEmpty { Text("No matching warnings.").foregroundStyle(.secondary) }
                }.padding(12)
            }.background(Color(nsColor: .textBackgroundColor))
            HStack {
                Text("\(matching.count) targets").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 680, height: 500)
    }
}
struct ModuleSettingsView: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    let module: Module
    @State var option: ModuleOptions
    let onSave: (() -> Void)?
    init(module: Module, initial: ModuleOptions, onSave: (() -> Void)? = nil) { self.module = module; self.onSave = onSave; _option = State(initialValue: initial) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(module.name).font(.system(size: 13, weight: .semibold)); Text("Localization routing").foregroundStyle(.secondary)
            ScrollView { Form {
                TextField("Key prefix", text: $option.prefix)
                Text("Example: \(KeyGenerator.key(prefix: option.prefix, english: "How to Open an account", existing: [:]))").font(.caption).foregroundStyle(.secondary)
                Picker("Existing table", selection: $option.resourcePath) {
                    Text("Choose a resource…").tag("")
                    ForEach(module.resources.filter { ["xcstrings", "strings"].contains($0.pathExtension) }, id: \.path) { url in Text(relativePath(url, root: module.root)).tag(url.path) }
                    if !option.resourcePath.isEmpty && !module.resources.contains(where: { $0.path == option.resourcePath }) { Text(option.resourcePath).tag(option.resourcePath) }
                }
                HStack {
                    TextField("Destination path", text: $option.resourcePath)
                    Button("Browse…") { let panel = NSOpenPanel(); panel.allowedContentTypes = [.data]; if panel.runModal() == .OK, let url = panel.url { option.resourcePath = url.path } }
                }
                Button("Use a new Localizable.xcstrings") { option.resourcePath = module.root.appendingPathComponent(module.kind == "Swift Package" ? "Resources/Localizable.xcstrings" : "Localizable.xcstrings").path }
                Button("Use a new legacy Localizable.strings") { option.resourcePath = module.root.appendingPathComponent((module.kind == "Swift Package" ? "Resources/" : "") + option.sourceLocale + ".lproj/Localizable.strings").path }
                TextField("Source locale", text: $option.sourceLocale)
                TextField("Swift bundle expression", text: $option.bundleExpression)
                Toggle("I confirm this bundle owns the selected resource", isOn: $option.bundleConfirmed)
                Text("Apps normally use .main; packages use .module. Frameworks require their own Bundle expression. Existing custom lookups are left for review.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Section("Swift replacement") {
                    Picker("Preset", selection: Binding(get: { option.replacementTemplate ?? "" }, set: { option.replacementTemplate = $0.isEmpty ? nil : $0 })) {
                        Text("Automatic NSLocalizedString").tag("")
                        Text("Key only").tag("{key}")
                        Text(".bundleLocalized").tag("{key}.bundleLocalized")
                        Text(".localized").tag("{key}.localized")
                        Text(".localize(key)").tag(".localize({key})")
                        if let template = option.replacementTemplate, !["", "{key}", "{key}.bundleLocalized", "{key}.localized", ".localize({key})"].contains(template) { Text("Custom").tag(template) }
                    }
                    TextField("Expression template", text: Binding(get: { option.replacementTemplate ?? "" }, set: { option.replacementTemplate = $0.isEmpty ? nil : $0 }))
                        .font(.system(size: 12, design: .monospaced))
                    Text("{key} includes Swift quotes. Leave empty for automatic output. Replaces the string expression, not Text or its other arguments. Existing localization calls keep their wrapper.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let issue = ReplacementTemplate.validationError(option.replacementTemplate) {
                        Text(issue).font(.caption).foregroundStyle(.red)
                    } else if let template = option.replacementTemplate, let example = try? ReplacementTemplate.render(template, key: option.prefix + ".how.to.open.an.account") {
                        Text("Text(" + example + ")").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }
                    Text("Your module must provide the custom API and route it to this resource's table and bundle. Syntax is checked here; build your project to verify types.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                TextField("Lokalise project override", text: $option.remoteProject)
                TextField("Branch override", text: $option.remoteBranch)
                Text("Leave the project empty to use the connection in Settings.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.columns).padding(8) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button(onSave == nil ? "Save Configuration" : "Save & Reanalyze") { model.saved.options[module.id] = option; model.analysis = nil; model.findings = []; model.persist(); dismiss(); onSave?() }.buttonStyle(.bordered).disabled(!KeyGenerator.validPrefix(option.prefix) || ReplacementTemplate.validationError(option.replacementTemplate) != nil) }
        }.padding(24).frame(width: 680, height: 640)
    }
}
struct StringsView: View {
    @EnvironmentObject var model: StudioModel
    @AppStorage("hideResultPatternsEnabled") private var hidePatterns = true
    @AppStorage("hideResultPatterns") private var hidePatternText = "{text}.Localized()"
    @State private var hiddenIDs: Set<String> = []
    @State var query = ""
    @State var status = "All actionable"
    @State var selection: String?
    @State private var configuration: Module?
    @State private var showReviewReasons = false
    @State private var showAnalysisWarnings = false
    @State private var sortOrder = [KeyPathComparator(\Finding.english)]
    private var selectableIDs: Set<String> { Set(filtered.filter { $0.status == .ready }.map(\.id)) }
    var filtered: [Finding] { model.findings.filter { finding in
        !hiddenIDs.contains(finding.id) && (query.isEmpty || finding.english.localizedCaseInsensitiveContains(query) || finding.key.localizedCaseInsensitiveContains(query) || finding.moduleName.localizedCaseInsensitiveContains(query)) && (status == "Everything" || (status == "All actionable" ? finding.status != .excluded && finding.status != .localized : finding.status.rawValue == status))
    } }
    private func refreshHiddenResults() {
        let matcher = FindingHidePatterns(hidePatternText)
        hiddenIDs = hidePatterns ? Set(model.findings.filter { matcher.matches($0) }.map(\.id)) : []
        // Hidden rows must not silently remain in the conversion preview.
        for index in model.findings.indices where hiddenIDs.contains(model.findings[index].id) {
            model.findings[index].selected = false
        }
        if let selection, hiddenIDs.contains(selection) { self.selection = nil }
    }
    private func selectReady(_ selected: Bool) {
        let ids = selectableIDs
        for index in model.findings.indices where ids.contains(model.findings[index].id) { model.findings[index].selected = selected }
    }
    private var reviewReasons: [(reason: String, count: Int)] {
        Dictionary(grouping: model.findings.filter { $0.status == .review }, by: \.reason)
            .map { (reason: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.reason < $1.reason : $0.count > $1.count }
    }
    var current: Finding? { model.findings.first { $0.id == selection } }
    var body: some View {
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: 10) {
                PageHeading(eyebrow: "02 / Understand your strings", title: "Localization Analysis", subtitle: "Safe conversions are selected. Review ambiguous contexts and interpolated text separately.")
                if model.analysis == nil { ContentUnavailableView("Analyze your modules first", systemImage: "text.magnifyingglass", description: Text("Choose one or more modules and run the Swift-aware analysis.")); Button("Analyze Selected Modules") { model.analyze() }.disabled(model.selected.isEmpty || model.busy) }
                else {
                    HStack(spacing: 14) { Metric(title: "Selected conversions", value: "\(model.readyCount)", icon: "checkmark.circle"); Metric(title: "Need review", value: "\(model.unresolvedCount)", icon: "eye"); Metric(title: "Already localized", value: "\(model.findings.filter { $0.status == .localized }.count)", icon: "globe") }
                    if !model.findings.contains(where: { $0.status == .ready }) && !reviewReasons.isEmpty {
                        HStack {
                            Label("No strings are ready to select yet", systemImage: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                            Button("Why?") { showReviewReasons = true }
                                .popover(isPresented: $showReviewReasons) {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Review required").font(.headline)
                                            ForEach(reviewReasons, id: \.reason) { issue in
                                                Text("\(issue.count) strings: \(issue.reason)").fixedSize(horizontal: false, vertical: true)
                                            }
                                            Text("Select a row for its exact reason. Dynamic or ambiguous strings require manual review.").foregroundStyle(.secondary)
                                        }.padding(16)
                                    }.frame(width: 420, height: 280)
                                }
                            Spacer()
                            Menu("Configure & Reanalyze…") {
                                ForEach(model.selected) { module in Button(module.name) { configuration = module } }
                            }.fixedSize()
                        }.padding(8).background(.orange.opacity(0.08))
                    }
                    if let warnings = model.analysis?.warnings, !warnings.isEmpty {
                        Button("\(warnings.count) analysis warnings") { showAnalysisWarnings = true }
                            .popover(isPresented: $showAnalysisWarnings) {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                                            Text(warning).font(.caption).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }.padding(16)
                                }.frame(width: 420, height: 280)
                            }
                    }
                    HStack { TextField("Search English text, keys, or modules", text: $query).textFieldStyle(.roundedBorder); Picker("Show", selection: $status) { Text("All actionable").tag("All actionable"); Text("Everything").tag("Everything"); ForEach(FindingStatus.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.frame(width: 230) }
                    HStack {
                        Toggle("Hide patterns", isOn: $hidePatterns).toggleStyle(.checkbox)
                        TextField("{text}.Localized(), {text}.localized, .localize({text}), ac.*", text: $hidePatternText)
                            .textFieldStyle(.roundedBorder)
                            .help("Comma-separated, case-sensitive patterns. {text} stands for a quoted Swift string. Use * for key formats, such as ac.*. Hidden rows are deselected.")
                        Text("\(hiddenIDs.count) hidden").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Select All Ready") { selectReady(true) }.disabled(selectableIDs.isEmpty)
                        Button("Deselect Ready") { selectReady(false) }.disabled(selectableIDs.isEmpty)
                        Text("\(selectableIDs.count) selectable in this filter").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Table(filtered.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("") { finding in Toggle("Register \(finding.english)", isOn: Binding(get: { model.findings.first { $0.id == finding.id }?.selected ?? false }, set: { value in if let i = model.findings.firstIndex(where: { $0.id == finding.id }) { model.findings[i].selected = value } })).labelsHidden().disabled(finding.status != .ready) }.width(28)
                        TableColumn("English value", value: \.english) { Text($0.english).lineLimit(2) }.width(min: 160, ideal: 280)
                        TableColumn("Key", value: \.key) { Text($0.key).font(.system(.caption, design: .monospaced)) }.width(min: 160, ideal: 260)
                        TableColumn("Module", value: \.moduleName).width(min: 80, ideal: 130)
                        TableColumn("Status", value: \.status.rawValue) { StatusBadge(status: $0.status.rawValue) }.width(150)
                    }.contextMenu(forSelectionType: String.self) { ids in
                        if let id = ids.first, let finding = model.findings.first(where: { $0.id == id }) {
                            Button("Open in Xcode at Line \(finding.line)") { model.openInXcode(finding) }
                        }
                    } primaryAction: { ids in
                        if let id = ids.first, let finding = model.findings.first(where: { $0.id == id }) {
                            model.openInXcode(finding)
                        }
                    }
                    .overlay(alignment: .topLeading, content: { TableSelectionHeader(
                        selectedCount: model.findings.filter { selectableIDs.contains($0.id) && $0.selected }.count,
                        totalCount: selectableIDs.count, enabled: !model.busy,
                        label: "Select all filtered safe conversions") { select in
                            let ids = selectableIDs
                            for index in model.findings.indices where ids.contains(model.findings[index].id) { model.findings[index].selected = select }
                        }.frame(width: 18, height: 22).padding(.leading, 5) })
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .clipped()
                    if let current {
                        ScrollView { VStack(alignment: .leading, spacing: 7) {
                            HStack { Text("\(current.file.lastPathComponent):\(current.line) · \(current.context)").font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle); Spacer(); Button("Open in Xcode") { model.openInXcode(current) }; Button("Configure & Reanalyze…") { configuration = model.modules.first { $0.id == current.moduleID } }; Button("Exclude") { model.exclude(current.id) } }
                            Text(current.reason).font(.caption).foregroundStyle(.secondary)
                            if let replacement = current.replacement { Text(replacement).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(4) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: min(100, viewport.size.height * 0.18)).background(Color(nsColor: .controlBackgroundColor))
                    }
                    HStack { Button("Reanalyze") { model.analyze() }; Button("Export analysis") { model.exportFindings() }; Spacer(); Text("\(filtered.count) occurrences").font(.caption).foregroundStyle(.secondary); Button("Preview \(model.readyCount) Conversions") { model.previewRegistration() }.buttonStyle(.bordered).disabled(model.readyCount == 0 || model.recoveryNeeded) }
                }
            }.padding(12)
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }.clipped().disabled(model.busy)
        .onAppear { refreshHiddenResults() }
        .onChange(of: hidePatterns) { refreshHiddenResults() }
        .onChange(of: hidePatternText) { refreshHiddenResults() }
        .onChange(of: model.findings.map(\.id)) { refreshHiddenResults() }
        .onChange(of: model.busy) { if !model.busy { refreshHiddenResults() } }
        .sheet(item: $configuration) { module in
            ModuleSettingsView(module: module, initial: model.saved.options[module.id] ?? ModuleOptions(module: module), onSave: { model.analyze() }).environmentObject(model)
        }
    }
}
struct StatusBadge: View {
    let status: String
    var success: Bool { ["Registered", "Imported", "Preserved", "Already localized", "Ready to register"].contains(status) }
    var body: some View {
        Label(status, systemImage: success ? "checkmark.circle" : (status == "Excluded" ? "minus.circle" : "exclamationmark.triangle.fill"))
            .font(.system(size: 11)).foregroundStyle(success || status == "Excluded" ? Color.secondary : Color.orange)
    }
}
