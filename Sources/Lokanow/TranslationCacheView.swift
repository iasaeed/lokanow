import SwiftUI

struct TranslationCacheView: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotate = false
    @State private var showDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.12), lineWidth: 3)
                    if model.cacheRefreshing {
                        Circle().trim(from: 0.08, to: 0.76)
                            .stroke(AngularGradient(colors: [.accentColor.opacity(0.15), .accentColor], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(rotate && !reduceMotion ? 360 : 0))
                            .animation(reduceMotion ? nil : .linear(duration: 1.4).repeatForever(autoreverses: false), value: rotate)
                            .onAppear { rotate = true }.onDisappear { rotate = false }
                    }
                    Image(systemName: model.cacheRefreshing ? "globe" : (model.cacheIssues.isEmpty ? "checkmark" : "exclamationmark"))
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(model.cacheIssues.isEmpty ? Color.accentColor : .orange)
                }.frame(width: 38, height: 38).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.cacheRefreshing ? "Updating translation library" : "Translation library")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.cacheRefreshing ? model.cacheActivity : (model.cacheMessage ?? "Ready for offline lookup"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    if model.cacheRefreshing {
                        Text("\(model.cacheKeyCount.formatted()) keys received · All available languages")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                if model.cacheRefreshing {
                    Button("Cancel Refresh") { model.cancelCacheRefresh() }
                        .disabled(model.cacheActivity == "Opening saved Lokalise connection…")
                } else {
                    if !model.cacheIssues.isEmpty { Button(showDetails ? "Hide Details" : "Show Details") { showDetails.toggle() } }
                    Button("Refresh") { model.refreshTranslationCache() }.disabled(model.token.isEmpty || model.busy)
                }
            }
            if model.cacheRefreshing {
                if model.cacheProgress > 0 { ProgressView(value: model.cacheProgress).accessibilityLabel("Projects refreshed") }
                else { ProgressView().progressViewStyle(.linear).accessibilityLabel("Downloading translations") }
            }
            if showDetails, !model.cacheIssues.isEmpty {
                ScrollView { Text(model.cacheIssues.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
            }
        }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.045))
    }
}
