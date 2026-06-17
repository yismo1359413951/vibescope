import SwiftUI
import OpenIslandCore

/// Settings pane for the rule-based auto-approve engine.
///
/// Edits are persisted to ``AutoApproveStore`` (the same UserDefaults the
/// bridge reads at decision time), so changes take effect immediately without
/// a restart. Each list is edited as free-form text, one entry per line.
struct AutoApproveSettingsPane: View {
    var model: AppModel

    private let store = AutoApproveStore()

    @State private var enabled = true
    @State private var dangerBehavior: AutoApproveBehavior = .ask
    @State private var allowToolsText = ""
    @State private var allowCommandsText = ""
    @State private var denyCommandsText = ""
    @State private var denyPathsText = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Toggle("启用自动批准", isOn: $enabled)
                Picker("命中危险规则时", selection: $dangerBehavior) {
                    Text("弹出询问（推荐）").tag(AutoApproveBehavior.ask)
                    Text("直接拒绝").tag(AutoApproveBehavior.deny)
                }
            } header: {
                Text("自动批准")
            } footer: {
                Text("命中“允许”规则的操作会自动放行、不打扰你；命中“危险/敏感”规则的按上面的设置处理；其余一律弹出询问交给你。")
                    .font(.caption)
            }

            listSection(
                title: "✅ 允许的工具（每行一个，如 Read、Grep、TodoWrite）",
                text: $allowToolsText
            )
            listSection(
                title: "✅ 允许的命令前缀（每行一个，如 git status、ls）",
                text: $allowCommandsText
            )
            listSection(
                title: "⛔️ 危险命令关键词（命令含这些就拦截，如 rm -rf、sudo）",
                text: $denyCommandsText
            )
            listSection(
                title: "⛔️ 敏感路径关键词（路径含这些就拦截，如 .ssh、.env）",
                text: $denyPathsText
            )

            Section {
                Button("恢复默认规则", role: .destructive) {
                    apply(.default)
                    save()
                }
            } footer: {
                Text("🔴 危险/敏感清单已内置对网络代理 / VPN 的保护（networksetup、scutil、clash、proxy 等），这类操作绝不会被自动批准。")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("自动批准")
        .onAppear {
            apply(store.rules)
            didLoad = true
        }
        .onChange(of: enabled) { _, _ in save() }
        .onChange(of: dangerBehavior) { _, _ in save() }
        .onChange(of: allowToolsText) { _, _ in save() }
        .onChange(of: allowCommandsText) { _, _ in save() }
        .onChange(of: denyCommandsText) { _, _ in save() }
        .onChange(of: denyPathsText) { _, _ in save() }
    }

    @ViewBuilder
    private func listSection(title: String, text: Binding<String>) -> some View {
        Section(title) {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 72)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
        }
    }

    /// Push a rule set into the editable fields.
    private func apply(_ rules: AutoApproveRules) {
        enabled = rules.enabled
        dangerBehavior = rules.dangerBehavior
        allowToolsText = rules.allowToolNames.joined(separator: "\n")
        allowCommandsText = rules.allowCommandPatterns.joined(separator: "\n")
        denyCommandsText = rules.denyCommandPatterns.joined(separator: "\n")
        denyPathsText = rules.denyPathPatterns.joined(separator: "\n")
    }

    /// Parse the editable fields back into a rule set and persist.
    private func save() {
        guard didLoad else { return }
        var rules = store.rules
        rules.enabled = enabled
        rules.dangerBehavior = dangerBehavior
        rules.allowToolNames = parse(allowToolsText)
        rules.allowCommandPatterns = parse(allowCommandsText)
        rules.denyCommandPatterns = parse(denyCommandsText)
        rules.denyPathPatterns = parse(denyPathsText)
        store.rules = rules
    }

    private func parse(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
