import Testing
import Foundation
@testable import OpenIslandCore

/// Verifies the rule-based auto-approve engine.
/// 验证按规则自动批准引擎。
struct ApprovalRuleEngineTests {
    private let engine = ApprovalRuleEngine(rules: .default)

    // MARK: - Allowlist

    /// A read-only tool in the allowlist is auto-approved.
    /// 白名单里的只读工具直接放行。
    @Test
    func allowlistedToolIsApproved() {
        let decision = engine.evaluate(ApprovalContext(toolName: "Read", filePaths: ["/tmp/x.txt"]))
        #expect(decision.behavior == .allow)
    }

    /// Tool matching is case-insensitive.
    /// 工具名匹配大小写不敏感。
    @Test
    func toolMatchIsCaseInsensitive() {
        #expect(engine.evaluate(ApprovalContext(toolName: "grep")).behavior == .allow)
        #expect(engine.evaluate(ApprovalContext(toolName: "GREP")).behavior == .allow)
    }

    /// A whitelisted command prefix is auto-approved.
    /// 命中白名单前缀的命令放行。
    @Test
    func allowlistedCommandPrefixIsApproved() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "git status --short")
        )
        #expect(decision.behavior == .allow)
        #expect(decision.matchedRule == "git status")
    }

    // MARK: - Danger overrides

    /// A danger command bounces to manual even when nothing else matches.
    /// 危险命令一律弹回手动。
    @Test
    func dangerCommandBouncesToAsk() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "rm -rf /Users/test/work")
        )
        #expect(decision.behavior == .ask)
        #expect(decision.matchedRule == "rm -rf")
    }

    /// Danger wins over a whitelisted prefix smuggled via chaining
    /// (`git status && rm -rf …`): the danger substring is found first.
    /// 即使用 `git status &&` 伪装，危险子串先命中，不放行。
    @Test
    func dangerWinsOverChainedAllowPrefix() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "git status && rm -rf ~/x")
        )
        #expect(decision.behavior == .ask)
    }

    /// A chained command whose prefix is whitelisted but which has no danger
    /// substring still must NOT be auto-allowed — the chaining guard forces the
    /// default (ask), so a second command can't ride along.
    /// 带链式操作符的命令即便前缀白名单、也不放行（防夹带第二条命令）。
    @Test
    func chainedAllowPrefixIsNotApproved() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "git status; open /Applications/Calculator.app")
        )
        #expect(decision.behavior == .ask)
        #expect(decision.matchedRule == nil)
    }

    /// Reading a sensitive path bounces to manual.
    /// 读敏感路径（.ssh）弹回手动。
    @Test
    func dangerPathBouncesToAsk() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "cat ~/.ssh/id_rsa")
        )
        #expect(decision.behavior == .ask)
    }

    /// A danger path declared via filePaths (non-shell tool) is caught too.
    /// 通过 filePaths 传入的敏感路径同样拦截。
    @Test
    func dangerPathViaFilePathsIsCaught() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Read", filePaths: ["/Users/test/.aws/credentials"])
        )
        #expect(decision.behavior == .ask)
    }

    /// 🔴 Network/VPN/proxy commands are never auto-approved (user hard rule).
    /// 🔴 网络/VPN/代理命令绝不自动批准（用户铁律）。
    @Test
    func vpnAndProxyCommandsNeverAutoApprove() {
        for command in [
            "networksetup -setwebproxy Wi-Fi 127.0.0.1 7890",
            "scutil --proxy",
            "export https_proxy=http://127.0.0.1:7890",
        ] {
            let decision = engine.evaluate(ApprovalContext(toolName: "Bash", command: command))
            #expect(decision.behavior == .ask, "should not auto-approve: \(command)")
        }
    }

    // MARK: - Defaults & master switch

    /// An unknown tool/command falls through to the default (ask).
    /// 未匹配的工具/命令走默认（ask）。
    @Test
    func unmatchedFallsBackToDefault() {
        let decision = engine.evaluate(
            ApprovalContext(toolName: "Bash", command: "some-unknown-tool --flag")
        )
        #expect(decision.behavior == .ask)
        #expect(decision.matchedRule == nil)
    }

    /// When disabled, every request resolves to ask regardless of rules.
    /// 关闭时一律 ask，无视规则。
    @Test
    func disabledAlwaysAsks() {
        var rules = AutoApproveRules.default
        rules.enabled = false
        let engine = ApprovalRuleEngine(rules: rules)
        let decision = engine.evaluate(ApprovalContext(toolName: "Read"))
        #expect(decision.behavior == .ask)
        #expect(decision.reason == "auto-approve disabled")
    }

    /// `dangerBehavior` is configurable to a hard deny.
    /// danger 行为可配置为直接拒绝。
    @Test
    func dangerBehaviorCanBeDeny() {
        var rules = AutoApproveRules.default
        rules.dangerBehavior = .deny
        let engine = ApprovalRuleEngine(rules: rules)
        let decision = engine.evaluate(ApprovalContext(toolName: "Bash", command: "sudo reboot"))
        #expect(decision.behavior == .deny)
    }

    // MARK: - Persistence shape

    /// Rules survive a JSON round-trip unchanged.
    /// 规则 JSON 往返不变。
    @Test
    func rulesCodableRoundTrips() throws {
        let original = AutoApproveRules.default
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AutoApproveRules.self, from: data)
        #expect(restored == original)
    }

    /// Partial JSON (missing fields) decodes by filling defaults — a
    /// hand-edited config never fails to load.
    /// 残缺 JSON 用默认值补齐，不会加载失败。
    @Test
    func partialJSONDecodesWithDefaults() throws {
        let json = Data(#"{"enabled": false}"#.utf8)
        let restored = try JSONDecoder().decode(AutoApproveRules.self, from: json)
        #expect(restored.enabled == false)
        #expect(restored.allowToolNames == AutoApproveRules.default.allowToolNames)
        #expect(restored.defaultBehavior == .ask)
    }
}
