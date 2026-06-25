import Foundation
import Testing
@testable import OpenIslandCore

/// End-to-end check that the auto-approve engine resolves Claude permission
/// requests through the bridge without waiting for a manual click.
///
/// Covers the *new* synchronous-resolution paths (allow / deny). The `.ask`
/// path is unchanged pre-existing behavior: it registers a pending interaction
/// and intentionally does not respond until the user clicks, so sending it
/// here would block — it is exercised by the rule-engine unit tests instead.
struct BridgeServerAutoApproveTests {
    private func permissionPayload(
        sessionID: String,
        toolName: String,
        command: String? = nil
    ) -> ClaudeHookPayload {
        let toolInput: ClaudeHookJSONValue? = command.map { .object(["command": .string($0)]) }
        return ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            sessionID: sessionID,
            toolName: toolName,
            toolInput: toolInput,
            toolUseID: "use-\(sessionID)"
        )
    }

    /// A whitelisted tool is auto-approved: the bridge answers with an `allow`
    /// directive immediately, no manual interaction required.
    /// 白名单工具直接被自动批准，桥立即回 allow 指令。
    @Test
    func whitelistedToolAutoApproves() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { .default })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(permissionPayload(sessionID: "allow-1", toolName: "Read"))
        )

        guard case .claudeHookDirective(.permissionRequest(.allow)) = response else {
            Issue.record("expected an allow directive, got \(String(describing: response))")
            return
        }
    }

    /// A whitelisted command prefix on Bash is auto-approved too.
    /// 命中白名单前缀的 Bash 命令也被自动批准。
    @Test
    func whitelistedCommandAutoApproves() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { .default })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                permissionPayload(sessionID: "allow-2", toolName: "Bash", command: "git status")
            )
        )

        guard case .claudeHookDirective(.permissionRequest(.allow)) = response else {
            Issue.record("expected an allow directive, got \(String(describing: response))")
            return
        }
    }

    /// With `dangerBehavior == .deny`, a dangerous command is auto-denied: the
    /// bridge answers with a `deny` directive without prompting.
    /// 当 danger 行为设为 deny 时，危险命令被自动拒绝。
    @Test
    func dangerousCommandAutoDeniesWhenConfigured() throws {
        let rules: AutoApproveRules = {
            var r = AutoApproveRules.default
            r.dangerBehavior = .deny
            return r
        }()

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { rules })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                permissionPayload(sessionID: "deny-1", toolName: "Bash", command: "rm -rf /tmp/x")
            )
        )

        guard case .claudeHookDirective(.permissionRequest(.deny)) = response else {
            Issue.record("expected a deny directive, got \(String(describing: response))")
            return
        }
    }

    /// When auto-approve is disabled, even a whitelisted tool must NOT be
    /// auto-resolved — it stays pending for a manual decision. We assert this
    /// without blocking by using a short timeout and expecting no response.
    /// 关闭自动批准后，白名单工具也不自动放行（保持挂起等手动）。
    @Test
    func disabledLeavesRequestPending() throws {
        let rules: AutoApproveRules = {
            var r = AutoApproveRules.default
            r.enabled = false
            return r
        }()

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { rules })
        try server.start()
        defer { server.stop() }

        // No auto-resolution → the server never responds → the client read
        // times out and throws. (A timeout here *is* the pass condition: it
        // proves the request stayed pending for a manual decision.)
        #expect(throws: BridgeTransportError.self) {
            _ = try BridgeCommandClient(socketURL: socketURL).send(
                .processClaudeHook(permissionPayload(sessionID: "pending-1", toolName: "Read")),
                timeout: 1
            )
        }
    }

    // MARK: - Codex

    private func codexPreToolPayload(sessionID: String, command: String) -> CodexHookPayload {
        CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: sessionID,
            transcriptPath: nil,
            turnID: "turn-1",
            toolName: "Bash",
            toolUseID: "tool-\(sessionID)",
            toolInput: CodexHookToolInput(command: command)
        )
    }

    private func codexPermissionPayload(
        sessionID: String,
        command: String,
        terminalApp: String? = nil,
        transcriptPath: String? = nil
    ) -> CodexHookPayload {
        CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: sessionID,
            terminalApp: terminalApp,
            transcriptPath: transcriptPath,
            turnID: "turn-1",
            toolName: "Bash",
            toolUseID: "tool-\(sessionID)",
            toolInput: CodexHookToolInput(command: command)
        )
    }

    /// A whitelisted Codex shell command is auto-approved: the bridge answers
    /// immediately (rather than leaving the preToolUse hook blocked).
    /// Codex 的白名单命令被自动批准，立即返回而非阻塞等手动。
    @Test
    func codexWhitelistedCommandAutoApproves() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { .default })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processCodexHook(codexPreToolPayload(sessionID: "codex-allow", command: "git status")),
            timeout: 5
        )

        #expect(response == .acknowledged)
    }

    /// Codex.app can emit a permission request without `transcript_path`.
    /// That still belongs to the user-facing approval flow and must not be
    /// filtered as an internal title-generation request.
    /// Codex 桌面端的审批事件即使没有 transcript，也不能被内部噪音过滤挡掉。
    @Test
    func codexAppPermissionRequestWithoutTranscriptAutoApproves() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { .default })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processCodexHook(
                codexPermissionPayload(
                    sessionID: "codex-app-permission",
                    command: "git status",
                    terminalApp: "Codex.app"
                )
            ),
            timeout: 5
        )

        guard case .codexHookDirective(.permissionRequest(.allow)) = response else {
            Issue.record("expected a codex permission allow directive, got \(String(describing: response))")
            return
        }
    }

    /// With `dangerBehavior == .deny`, a dangerous Codex command is auto-denied.
    /// 危险行为设为 deny 时，Codex 危险命令被自动拒绝。
    @Test
    func codexDangerousCommandAutoDeniesWhenConfigured() throws {
        let rules: AutoApproveRules = {
            var r = AutoApproveRules.default
            r.dangerBehavior = .deny
            return r
        }()

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, autoApproveRulesProvider: { rules })
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processCodexHook(codexPreToolPayload(sessionID: "codex-deny", command: "rm -rf build")),
            timeout: 5
        )

        guard case .codexHookDirective(.deny) = response else {
            Issue.record("expected a codex deny directive, got \(String(describing: response))")
            return
        }
    }

    // MARK: - Per-session pause（按会话暂停自动批准）

    /// 会话被暂停时：原本会自动放行的白名单工具改为保持挂起（等手动），
    /// 即 allow 被改判为 ask。非暂停会话不受影响。
    @Test
    func pausedSessionHoldsOtherwiseAllowedRequest() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(
            socketURL: socketURL,
            autoApproveRulesProvider: { .default },
            autoApprovePausedProvider: { $0 == "paused-1" }
        )
        try server.start()
        defer { server.stop() }

        // 暂停会话：白名单 Read 也不放行 → 挂起 → 客户端读超时（超时即通过）。
        #expect(throws: BridgeTransportError.self) {
            _ = try BridgeCommandClient(socketURL: socketURL).send(
                .processClaudeHook(permissionPayload(sessionID: "paused-1", toolName: "Read")),
                timeout: 1
            )
        }

        // 非暂停会话：同样的白名单 Read 仍自动放行。
        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(permissionPayload(sessionID: "active-1", toolName: "Read"))
        )
        guard case .claudeHookDirective(.permissionRequest(.allow)) = response else {
            Issue.record("expected allow for non-paused session, got \(String(describing: response))")
            return
        }
    }

    /// 安全红线不被会话开关绕过：会话暂停 + danger=deny 时，危险命令仍然 deny
    /// （暂停只把 allow→ask，不会把 deny→ask）。
    @Test
    func pausedSessionStillDeniesDangerousCommand() throws {
        let rules: AutoApproveRules = {
            var r = AutoApproveRules.default
            r.dangerBehavior = .deny
            return r
        }()

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(
            socketURL: socketURL,
            autoApproveRulesProvider: { rules },
            autoApprovePausedProvider: { _ in true }
        )
        try server.start()
        defer { server.stop() }

        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                permissionPayload(sessionID: "paused-deny", toolName: "Bash", command: "rm -rf /tmp/x")
            )
        )
        guard case .claudeHookDirective(.permissionRequest(.deny)) = response else {
            Issue.record("expected deny to survive pause, got \(String(describing: response))")
            return
        }
    }
}
