import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LocalizeCore

@MainActor final class StudioModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable { case modules = "Modules", strings = "Strings", translations = "Translations", reports = "Reports"; var id: String { rawValue }; var icon: String { switch self { case .modules: "square.stack.3d.up"; case .strings: "text.quote"; case .translations: "globe"; case .reports: "doc.text" } } }
    @Published var page: Page = .modules
    @Published var root: URL?
    @Published var modules: [Module] = []
    @Published var saved = SavedProject()
    @Published var analysis: Analysis?
    @Published var findings: [Finding] = []
    @Published var plan: ChangePlan?
    @Published var reports: [OperationReport] = []
    @Published var busy = false
    @Published var progress = 0.0
    @Published var activity = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var token = ""
    @Published var projects: [RemoteProject] = []
    @Published var languages: [RemoteLanguage] = []
    @Published var connected = false
    @Published var languageMap = ["ar": "ar"]
    @Published var sourceLocale = "en"
    @Published var defaultProject = ""
    @Published var defaultBranch = ""
    @Published var requireReviewed = false
    @Published var replaceExisting = false
    @Published var useCache = true
    @Published var cacheDate: Date?
    @Published var matchingKeys: [String: [RemoteKey]] = [:]
    @Published var recoveryNeeded = false
    @Published var cacheRefreshing = false
    @Published var cacheActivity = ""
    @Published var cacheProgress = 0.0
    @Published var cacheKeyCount = 0
    @Published var cacheMessage: String?
    @Published var cacheIssues: [String] = []
    private var cacheTask: Task<Void, Never>?
    private var cacheActiveProject: String?
    private var didStart = false
    private let translationCache = TranslationCache(directory: Storage.directory)
    private var task: Task<Void, Never>?
    private var accessURL: URL?
    var selected: [Module] { modules.filter { saved.selectedModules.contains($0.id) && !(saved.removedModules ?? []).contains($0.id) } }
    var readyCount: Int { findings.filter { $0.selected && $0.status == .ready }.count }
    var unresolvedCount: Int { findings.filter { [.review, .dynamic].contains($0.status) }.count }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        do {
            reports = try Storage.load([OperationReport].self, name: "reports") ?? []
        } catch { self.error = error.localizedDescription }
        defaultProject = UserDefaults.standard.string(forKey: "remoteProject") ?? ""
        defaultBranch = UserDefaults.standard.string(forKey: "remoteBranch") ?? ""
        sourceLocale = UserDefaults.standard.string(forKey: "sourceLocale") ?? "en"
        if let data = UserDefaults.standard.data(forKey: "languageMap"), let value = try? JSONDecoder().decode([String: String].self, from: data) { languageMap = value }
        requireReviewed = UserDefaults.standard.bool(forKey: "reviewed")
    }
    func start() async {
        guard !didStart, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        didStart = true
        restoreProject()
        // Complete restoration so saved module branch overrides participate in the refresh.
        await task?.value
        cacheRefreshing = true; cacheActivity = "Opening saved Lokalise connection…"
        do { token = try await Self.work { try Credentials.read() } }
        catch { cacheIssues = [error.localizedDescription]; cacheMessage = "Could not open the saved connection." }
        cacheRefreshing = false
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !defaultProject.isEmpty, let snapshot = try? await translationCache.load(token: token, project: remoteID(defaultProject, defaultBranch)) { cacheDate = snapshot.date }
            await task?.value
            refreshTranslationCache()
        }
    }

    func refreshTranslationCache() {
        guard !cacheRefreshing, !busy, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let credential = token, client = LokaliseClient(token: token)
        var configured = Set<String>()
        if !defaultProject.isEmpty { configured.insert(remoteID(defaultProject, defaultBranch)) }
        for option in saved.options.values where !option.remoteProject.isEmpty {
            configured.insert(remoteID(option.remoteProject, option.remoteBranch))
        }
        cacheRefreshing = true; cacheProgress = 0; cacheKeyCount = 0
        cacheIssues = []; cacheMessage = nil; cacheActivity = "Loading Lokalise projects…"
        cacheTask = Task {
            defer { cacheRefreshing = false; cacheTask = nil; cacheActiveProject = nil }
            do {
                var available: [RemoteProject] = []
                do {
                    available = try await client.projects()
                    try Task.checkCancellation()
                    projects = available; connected = true
                } catch {
                    try Task.checkCancellation()
                    guard !configured.isEmpty else { throw error }
                    cacheIssues.append("Project list: " + error.localizedDescription)
                }
                let scopes = Set(available.map(\.id)).union(configured).sorted()
                if scopes.isEmpty { cacheMessage = "No accessible Lokalise projects to cache."; return }
                var completed = 0, successful = 0
                for id in scopes {
                    try Task.checkCancellation()
                    let label = available.first { $0.id == id }?.name ?? id
                    cacheActivity = "\(label) · Project \(completed + 1) of \(scopes.count)"
                    cacheActiveProject = id
                    let keysBeforeProject = cacheKeyCount
                    do {
                        let snapshot = try await translationCache.refresh(client: client, token: credential, project: id) { count in
                            Task { @MainActor [weak self] in
                                guard let self, self.cacheRefreshing, self.token == credential, self.cacheActiveProject == id else { return }
                                self.cacheKeyCount = keysBeforeProject + count
                            }
                        }
                        try Task.checkCancellation()
                        cacheKeyCount = keysBeforeProject + snapshot.keys.count
                        successful += 1
                        if id == remoteID(defaultProject, defaultBranch) { cacheDate = snapshot.date }
                    } catch {
                        try Task.checkCancellation()
                        cacheIssues.append(label + ": " + error.localizedDescription)
                        cacheKeyCount = keysBeforeProject
                    }
                    cacheActiveProject = nil
                    completed += 1; cacheProgress = Double(completed) / Double(scopes.count)
                }
                try Task.checkCancellation()
                cacheMessage = cacheIssues.isEmpty
                    ? "Translation cache updated · \(successful) projects · \(cacheKeyCount.formatted()) keys"
                    : "Updated \(successful) of \(scopes.count) projects. Previous snapshots remain available for failed projects."
                if !defaultProject.isEmpty {
                    do { languages = try await client.languages(project: remoteID(defaultProject, defaultBranch)) }
                    catch { try Task.checkCancellation(); cacheIssues.append("Languages: " + error.localizedDescription) }
                }
            } catch is CancellationError {
                cacheMessage = "Cache refresh cancelled. Completed snapshots and previous cached translations remain available."
            } catch let error as URLError where error.code == .cancelled {
                cacheMessage = "Cache refresh cancelled. Previous cached translations remain available."
            } catch {
                cacheIssues.append(error.localizedDescription)
                cacheMessage = "Could not update translations. Previous cached translations remain available."
            }
        }
    }
    func cancelCacheRefresh() { cacheTask?.cancel() }
    func restoreProject() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        guard root == nil, let data = UserDefaults.standard.data(forKey: "projectBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { notice = "The saved project permission has changed. Select the folder again if access fails." }
            openProject(url)
        } catch { notice = "Select your project folder to renew access." }
    }
    func chooseProject() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Open Project"; panel.message = "Choose the folder containing your Xcode workspace, project, or Swift package."
        if panel.runModal() == .OK, let url = panel.url { openProject(url) }
    }
    func openProject(_ url: URL) {
        guard !busy else { return }
        accessURL?.stopAccessingSecurityScopedResource(); _ = url.startAccessingSecurityScopedResource(); accessURL = url
        modules = []; recoveryNeeded = false
        root = url; analysis = nil; findings = []; plan = nil; matchingKeys = [:]; page = .modules
        do {
            saved = try Storage.load(SavedProject.self, name: "project-" + stableID(url.path)) ?? SavedProject()
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "projectBookmark") }
        } catch { self.error = error.localizedDescription }
        discover()
    }
    func closeProject() {
        guard !busy else { return }
        persist()
        accessURL?.stopAccessingSecurityScopedResource(); accessURL = nil
        root = nil; modules = []; saved = SavedProject(); analysis = nil; findings = []
        plan = nil; matchingKeys = [:]; recoveryNeeded = false; page = .modules
        UserDefaults.standard.removeObject(forKey: "projectBookmark")
        notice = "Project closed. Choose another project to continue."
    }
    func removeModule(_ id: String) {
        guard !busy else { return }
        saved.removedModules = (saved.removedModules ?? []).union([id])
        saved.selectedModules.remove(id)
        analysis = nil; findings = []; plan = nil; matchingKeys = [:]
        persist()
        notice = "Module removed from this workspace. Its source files are unchanged. Use Show Removed to restore it."
    }
    func restoreModule(_ id: String) {
        guard !busy else { return }
        saved.removedModules?.remove(id); persist(); notice = "Module restored. Select it to include it in analysis."
    }
    func discover() {
        guard let root else { return }
        let exclusions = Discovery.defaultExclusions.union(saved.exclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        run("Discovering build targets…") {
            let result = try await Self.work { try Discovery.discover(root: root, exclusions: exclusions) }
            self.modules = result
            for module in result where self.saved.options[module.id] == nil { self.saved.options[module.id] = ModuleOptions(module: module) }
            self.saved.selectedModules.formIntersection(Set(result.map(\.id)))
            if self.saved.selectedModules.isEmpty, result.count == 1, !(self.saved.removedModules ?? []).contains(result[0].id) { self.saved.selectedModules = [result[0].id] }
            self.recoveryNeeded = try Transactions.pending(root: root) != nil
            self.persist()
        }
    }
    func openInXcode(_ finding: Finding) {
        let file = finding.file.standardizedFileURL
        guard file.isFileURL, FileManager.default.isReadableFile(atPath: file.path) else {
            error = "The source file is no longer readable. Reopen the project and analyze again."
            return
        }
        guard let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else {
            error = "Xcode was not found by macOS. Install or launch Xcode once, then retry."
            return
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.appleEvent = try XcodeSourceLocation.event(file: file, line: finding.line)
            NSWorkspace.shared.open([file], withApplicationAt: xcode, configuration: configuration) { [weak self] _, failure in
                guard let failure else { return }
                Task { @MainActor in
                    self?.error = "macOS could not open this source in Xcode: " + failure.localizedDescription
                }
            }
        } catch {
            self.error = "Could not prepare the source location for Xcode: " + error.localizedDescription
        }
    }

    func analyze() {
        guard !selected.isEmpty else { error = "Select one or more modules first."; return }
        persist(); let selected = selected, all = modules, options = saved.options, exclusions = saved.excludedFindings
        let wrappers = Set(saved.wrappers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        run("Analyzing Swift source…") {
            let result = try await Self.work {
                try Analyzer.analyze(modules: selected, allModules: all, options: options, exclusions: exclusions, wrappers: wrappers) { current, total, file in
                    Task { @MainActor in self.progress = Double(current) / Double(max(total, 1)); self.activity = "Analyzing \(file) · \(current)/\(total) files" }
                }
            }
            self.analysis = result; self.findings = result.findings; self.page = .strings; self.plan = nil
            self.notice = "Analyzed \(result.files) files. \(self.readyCount) safe conversions; \(self.unresolvedCount) items need review."
        }
    }
    func editFindingKey(id: String, key: String) async -> String? {
        guard !busy, let analysis else { return "Analyze the project before editing a key." }
        let currentFindings = findings, options = saved.options
        busy = true; activity = "Validating localization key…"
        defer { busy = false }
        do {
            let updated = try await Self.work {
                try FindingKeyEditor.edit(id: id, key: key, findings: currentFindings, snapshots: analysis.snapshots, options: options)
            }
            findings = updated; plan = nil
            notice = "Key updated for matching occurrences in this module. Preview conversions to apply it to files."
            return nil
        } catch { return error.localizedDescription }
    }
    func previewRegistration() {
        guard let root, let analysis else { return }
        do { plan = try Planner.registration(root: root, findings: findings, snapshots: analysis.snapshots, options: saved.options, modules: modules) }
        catch { self.error = error.localizedDescription }
    }
    func applyPlan() {
        guard let plan else { return }
        run("Applying \(plan.changes.count) file changes…") {
            try await Self.work { try Transactions.apply(plan) }
            self.addReport(title: plan.title, rows: plan.rows)
            self.plan = nil; self.analysis = nil; self.findings = []; self.page = .reports
            // Discover resources created in synchronized target folders for the next operation.
            self.modules = try await Self.work { try Discovery.discover(root: plan.root) }
            self.notice = "\(plan.title) completed. \(plan.changes.count) files updated; backups and undo are available."
        }
    }
    func undo() {
        guard let root else { return }
        run("Restoring the last operation…") {
            try await Self.work { try Transactions.undo(root: root) }
            self.analysis = nil; self.findings = []; self.plan = nil; self.notice = "Last operation undone. Reanalyze to refresh the project state."
        }
    }
    func recover() {
        guard let root else { return }
        run("Recovering interrupted operation…") { try await Self.work { try Transactions.recover(root: root) }; self.recoveryNeeded = false; self.notice = "Interrupted changes restored from the operation journal." }
    }
    @discardableResult func saveSettings() -> Bool {
        do {
            try Credentials.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            UserDefaults.standard.set(defaultProject, forKey: "remoteProject"); UserDefaults.standard.set(defaultBranch, forKey: "remoteBranch")
            UserDefaults.standard.set(sourceLocale, forKey: "sourceLocale"); UserDefaults.standard.set(requireReviewed, forKey: "reviewed")
            UserDefaults.standard.set(try JSONEncoder().encode(languageMap), forKey: "languageMap")
            persist(); notice = "Settings saved. Your token is stored in Keychain."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func testConnection() {
        guard !cacheRefreshing else { return }
        guard saveSettings() else { return }; connected = false; let client = LokaliseClient(token: token)
        run("Connecting to Lokalise…") {
            self.projects = try await client.projects(); self.connected = true; self.notice = "Connected. \(self.projects.count) projects available."
            if self.defaultProject.isEmpty, let first = self.projects.first { self.defaultProject = first.id }
            if !self.defaultProject.isEmpty { self.languages = try await client.languages(project: self.remoteID(self.defaultProject, self.defaultBranch)) }
            Task { @MainActor in await self.task?.value; self.refreshTranslationCache() }
        }
    }
    func loadLanguages() {
        let client = LokaliseClient(token: token), id = remoteID(defaultProject, defaultBranch)
        run("Loading project languages…") { self.languages = try await client.languages(project: id) }
    }
    func disconnect() {
        guard !cacheRefreshing, !busy else { return }
        cacheMessage = nil; cacheIssues = []; cacheDate = nil
        do { try Credentials.save(""); token = ""; connected = false; projects = []; languages = []; matchingKeys = [:]; try Storage.clearCache(); notice = "Disconnected and cleared cached remote keys." }
        catch { self.error = error.localizedDescription }
    }
    func clearCache() { guard !cacheRefreshing, !busy else { return }; cacheMessage = nil; cacheIssues = []; do { try Storage.clearCache(); cacheDate = nil; notice = "Translation cache cleared." } catch { self.error = error.localizedDescription } }
    func previewImport() {
        guard !cacheRefreshing else { notice = "Wait for the cache refresh, or cancel it to use existing snapshots."; return }
        guard let root, !selected.isEmpty else { error = "Select modules before importing."; return }
        guard !languageMap.isEmpty else { error = "Select at least one target language."; return }
        guard saveSettings() else { return }
        let selected = selected, configs = saved.options, token = token, defaultProject = defaultProject, defaultBranch = defaultBranch, useCache = useCache
        var importOptions = ImportOptions(); importOptions.sourceLocale = sourceLocale; importOptions.languages = languageMap; importOptions.requireReviewed = requireReviewed; importOptions.replaceExisting = replaceExisting; importOptions.preferredKeys = saved.remoteMappings
        let resolvedImportOptions = importOptions
        run("Finding existing translations by English value…") {
            var combinedChanges: [URL: FileChange] = [:], rows: [ReportRow] = [], fetched: [String: [RemoteKey]] = [:]
            self.matchingKeys = [:]
            for module in selected {
                try Task.checkCancellation()
                let config = configs[module.id] ?? ModuleOptions(module: module)
                let id = self.remoteID(config.remoteProject.isEmpty ? defaultProject : config.remoteProject, config.remoteProject.isEmpty ? defaultBranch : config.remoteBranch)
                guard !id.isEmpty else { throw StudioError.message("Choose a Lokalise project in Settings or map \(module.name) to one.") }
                let keys: [RemoteKey]
                if let existing = fetched[id] { keys = existing }
                else if useCache {
                    guard let cached = try await self.translationCache.load(token: token, project: id) else { throw StudioError.message("No cached translations exist for this account/project. Refresh the cache or turn off cache mode to fetch them.") }
                    keys = cached.keys; self.cacheDate = cached.date
                } else {
                    let snapshot = try await self.translationCache.refresh(client: LokaliseClient(token: token), token: token, project: id)
                    keys = snapshot.keys; self.cacheDate = snapshot.date
                }
                fetched[id] = keys; self.matchingKeys[module.id] = keys
                let result = try await Self.work { try ImportPlanner.plan(root: root, module: module, config: config, remote: keys, options: resolvedImportOptions) }
                for change in result.changes {
                    if let previous = combinedChanges[change.url], previous.after != change.after { throw StudioError.message("Selected modules propose different translations for a shared resource. Import those modules separately after resolving ownership.") }
                    combinedChanges[change.url] = change
                }
                rows += result.rows
            }
            let plan = ChangePlan(title: "Import translations", root: root, changes: combinedChanges.values.sorted { $0.url.path < $1.url.path }, rows: rows)
            if plan.changes.isEmpty { self.addReport(title: "Translation lookup", rows: rows); self.page = .reports; self.notice = "Lookup complete. No files changed; review the report for unresolved items." }
            else { self.plan = plan }
        }
    }
    func remoteID(_ project: String, _ branch: String) -> String { project + (branch.isEmpty ? "" : ":" + branch) }
    func exclude(_ id: String) {
        saved.excludedFindings.insert(id)
        if let index = findings.firstIndex(where: { $0.id == id }) { findings[index].status = .excluded; findings[index].selected = false; findings[index].reason = "Excluded by saved project rule." }
        persist()
    }
    func exportFindings() {
        guard let root else { return }
        let rows = findings.map { ReportRow(module: $0.moduleName, key: $0.key, english: $0.english, status: $0.status.rawValue, reason: $0.reason, source: relativePath($0.file, root: root) + ":\($0.line)", destination: $0.resource.map { relativePath($0, root: root) } ?? "") }
        addReport(title: "Analysis", rows: rows); page = .reports
    }
    func addReport(title: String, rows: [ReportRow]) {
        reports.insert(OperationReport(title: title, rows: rows), at: 0)
        do { try Storage.save(reports, name: "reports") } catch { self.error = "Files were processed, but the report could not be saved: \(error.localizedDescription)" }
    }
    func export(_ rows: [ReportRow], format: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "localization-report.\(format)"; panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if format == "json" { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; data = try encoder.encode(rows) }
            else { data = Data((format == "csv" ? ReportExporter.csv(rows) : ReportExporter.markdown(rows)).utf8) }
            try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func copy(_ rows: [ReportRow]) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ReportExporter.markdown(rows), forType: .string); notice = "Copied \(rows.count) report items." }
    func persist() { guard let root else { return }; do { try Storage.save(saved, name: "project-" + stableID(root.path)) } catch { self.error = error.localizedDescription } }
    func cancel() { task?.cancel(); activity = "Cancelling…" }
    func run(_ title: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; progress = 0; activity = title; error = nil; notice = nil
        task = Task {
            defer { busy = false; activity = ""; task = nil }
            do { try await operation() }
            catch is CancellationError { notice = "Operation cancelled. No pending preview was applied." }
            catch let error as URLError where error.code == .cancelled { notice = "Operation cancelled." }
            catch { self.error = error.localizedDescription }
        }
    }
    nonisolated static func work<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
