import Foundation

/// Recommendation produced by the auto-approve engine for a single permission
/// request.
///
/// - `allow`: auto-approve without bothering the user.
/// - `ask`: bounce to the manual island prompt (the safe fallback).
/// - `deny`: auto-reject.
public enum AutoApproveBehavior: String, Codable, Sendable {
    case allow
    case ask
    case deny
}

/// Normalized, agent-agnostic view of a permission request fed to the engine.
///
/// Different agents (Claude Code, Cursor, Codex, …) describe a pending action
/// differently on the wire. Callers flatten those payloads into this struct so
/// the rule engine never has to know which agent produced the request.
public struct ApprovalContext: Equatable, Sendable {
    /// The agent that produced the request, when known.
    public var agent: AgentIdentifier?
    /// The tool being invoked, e.g. "Bash", "Read", "Edit", "Write".
    public var toolName: String
    /// The shell command for Bash-like tools (`nil` for non-shell tools).
    public var command: String?
    /// File paths the tool would touch (reads, writes, edits).
    public var filePaths: [String]
    /// The session's working directory, when known.
    public var cwd: String?

    public init(
        agent: AgentIdentifier? = nil,
        toolName: String,
        command: String? = nil,
        filePaths: [String] = [],
        cwd: String? = nil
    ) {
        self.agent = agent
        self.toolName = toolName
        self.command = command
        self.filePaths = filePaths
        self.cwd = cwd
    }
}

/// The engine's verdict plus a human-readable explanation, surfaced in logs and
/// (eventually) the island UI so the user can see *why* something was
/// auto-approved or bounced.
public struct AutoApproveDecision: Equatable, Sendable {
    public var behavior: AutoApproveBehavior
    public var reason: String
    public var matchedRule: String?

    public init(behavior: AutoApproveBehavior, reason: String, matchedRule: String? = nil) {
        self.behavior = behavior
        self.reason = reason
        self.matchedRule = matchedRule
    }
}

/// User-editable rule set driving auto-approval. `Codable` so it can be
/// persisted (see ``AutoApproveStore``) and edited from the settings UI.
///
/// Evaluation order is **safety first**: danger rules are checked before the
/// allowlist, so no allow rule can ever override a danger match.
public struct AutoApproveRules: Codable, Equatable, Sendable {
    /// Master switch. When `false`, every request resolves to `.ask`.
    public var enabled: Bool

    /// Tool names that are always safe to auto-approve (matched
    /// case-insensitively), e.g. read-only tools.
    public var allowToolNames: [String]

    /// Command prefixes that are safe to auto-approve. Matched against the
    /// trimmed command, case-insensitively, as a **prefix** — and only when the
    /// command contains no shell-chaining operators (see ``hasShellChaining``),
    /// so a whitelisted prefix can't be used to smuggle a second command.
    public var allowCommandPatterns: [String]

    /// Substrings that mark a command as dangerous (matched anywhere,
    /// case-insensitively). A match yields ``dangerBehavior``.
    public var denyCommandPatterns: [String]

    /// Substrings that mark a touched path as sensitive (matched anywhere,
    /// case-insensitively). A match yields ``dangerBehavior``.
    public var denyPathPatterns: [String]

    /// What a danger match resolves to. Defaults to `.ask` (bounce to manual)
    /// rather than `.deny`, so the agent isn't hard-blocked — the user decides.
    public var dangerBehavior: AutoApproveBehavior

    /// What an unmatched request resolves to. Defaults to `.ask`.
    public var defaultBehavior: AutoApproveBehavior

    public init(
        enabled: Bool,
        allowToolNames: [String],
        allowCommandPatterns: [String],
        denyCommandPatterns: [String],
        denyPathPatterns: [String],
        dangerBehavior: AutoApproveBehavior = .ask,
        defaultBehavior: AutoApproveBehavior = .ask
    ) {
        self.enabled = enabled
        self.allowToolNames = allowToolNames
        self.allowCommandPatterns = allowCommandPatterns
        self.denyCommandPatterns = denyCommandPatterns
        self.denyPathPatterns = denyPathPatterns
        self.dangerBehavior = dangerBehavior
        self.defaultBehavior = defaultBehavior
    }

    /// Tolerate older/partial JSON: any missing field falls back to its
    /// `default` value so a hand-edited or migrated config never fails to load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AutoApproveRules.default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        allowToolNames = try c.decodeIfPresent([String].self, forKey: .allowToolNames) ?? d.allowToolNames
        allowCommandPatterns = try c.decodeIfPresent([String].self, forKey: .allowCommandPatterns) ?? d.allowCommandPatterns
        denyCommandPatterns = try c.decodeIfPresent([String].self, forKey: .denyCommandPatterns) ?? d.denyCommandPatterns
        denyPathPatterns = try c.decodeIfPresent([String].self, forKey: .denyPathPatterns) ?? d.denyPathPatterns
        dangerBehavior = try c.decodeIfPresent(AutoApproveBehavior.self, forKey: .dangerBehavior) ?? d.dangerBehavior
        defaultBehavior = try c.decodeIfPresent(AutoApproveBehavior.self, forKey: .defaultBehavior) ?? d.defaultBehavior
    }

    /// Conservative, safety-first defaults that are useful out of the box.
    ///
    /// Note the danger list hard-protects the user's network/VPN setup
    /// (`networksetup`, `scutil`, proxy/Clash configuration): those can never be
    /// auto-approved and always bounce to a manual prompt.
    public static let `default` = AutoApproveRules(
        enabled: true,
        allowToolNames: [
            "Read", "Glob", "Grep", "LS", "NotebookRead", "TodoWrite",
        ],
        allowCommandPatterns: [
            "git status", "git diff", "git log", "git branch", "git show",
            "git stash list", "git remote -v",
            "ls", "pwd", "cat ", "head ", "tail ", "echo ", "which ", "wc ",
            "grep ", "rg ", "find ", "file ", "stat ", "du ", "df ",
            "swift build", "swift test", "npm test", "npm run lint",
            "pnpm test", "yarn test", "cargo build", "cargo test", "go test",
            "make test", "pytest",
        ],
        denyCommandPatterns: [
            // Destructive filesystem
            "rm -rf", "rm -fr", "rm -r ", "rmdir", "mkfs", "dd if=", "dd of=",
            "shred ", "> /dev/", ">/dev/",
            // Privilege / system
            "sudo", "su ", "chmod 777", "chmod -R", "chown -R",
            "launchctl", "defaults write", "systemsetup", "spctl",
            // Process / fork bomb
            "kill -9", "killall", "pkill", ":(){",
            // Git history rewrite / force
            "git push", "--force", "-f origin", "reset --hard", "git clean",
            "filter-branch", "rebase",
            // Network egress / remote exec
            "curl", "wget", "| sh", "|sh", "| bash", "|bash", "nc ", "ncat ",
            "ssh ", "scp ", "telnet", "eval ", "base64 -d", "base64 --decode",
            // 🔴 Network / VPN / proxy — never auto-approve (user hard rule)
            "networksetup", "scutil", "-setwebproxy", "-setsecurewebproxy",
            "-setsocksfirewallproxy", "-setautoproxyurl", "clashx", "clash",
            "http_proxy", "https_proxy", "all_proxy", "proxychains",
        ],
        denyPathPatterns: [
            ".ssh", "id_rsa", "id_ed25519", "authorized_keys", "known_hosts",
            ".aws", ".gnupg", ".netrc", ".npmrc", ".pypirc",
            ".env", "credentials", "secret", "token", ".pem", ".key",
            "Keychains", "/etc/", "/private/etc/",
            // 🔴 network/VPN/proxy config — never auto-approve (user hard rule)
            "clash", "ClashX", ".vpn", "proxy",
            // hook config — don't let the agent silently rewire its own hooks
            "/.claude/settings", "/.codex/config", "/.cursor/hooks",
        ],
        dangerBehavior: .ask,
        defaultBehavior: .ask
    )

    private enum CodingKeys: String, CodingKey {
        case enabled, allowToolNames, allowCommandPatterns
        case denyCommandPatterns, denyPathPatterns, dangerBehavior, defaultBehavior
    }
}

/// Pure, deterministic evaluator: given a request and a rule set, returns a
/// decision. No I/O, no global state — trivially unit-testable and safe to call
/// from the bridge's hot path.
public struct ApprovalRuleEngine: Sendable {
    public let rules: AutoApproveRules

    public init(rules: AutoApproveRules) {
        self.rules = rules
    }

    /// Shell operators that allow a second command to ride along. If any are
    /// present we refuse to auto-allow (a whitelisted prefix could otherwise
    /// smuggle `git status && rm -rf ~`).
    static func hasShellChaining(_ command: String) -> Bool {
        for token in ["&&", "||", ";", "|", "`", "$(", "\n", ">", "<"] {
            if command.contains(token) { return true }
        }
        return false
    }

    public func evaluate(_ context: ApprovalContext) -> AutoApproveDecision {
        guard rules.enabled else {
            return AutoApproveDecision(behavior: .ask, reason: "auto-approve disabled")
        }

        // 1. Danger checks first — safety always wins over any allow rule.
        if let command = context.command {
            let lowered = command.lowercased()
            for pattern in rules.denyCommandPatterns where lowered.contains(pattern.lowercased()) {
                return AutoApproveDecision(
                    behavior: rules.dangerBehavior,
                    reason: "danger command rule matched: \(pattern)",
                    matchedRule: pattern
                )
            }
        }
        // Danger paths are matched against both declared file paths and, for
        // shell tools, the raw command (e.g. `cat ~/.ssh/id_rsa`).
        let pathHaystacks = context.filePaths + (context.command.map { [$0] } ?? [])
        for pattern in rules.denyPathPatterns {
            let loweredPattern = pattern.lowercased()
            for haystack in pathHaystacks where haystack.lowercased().contains(loweredPattern) {
                return AutoApproveDecision(
                    behavior: rules.dangerBehavior,
                    reason: "danger path rule matched: \(pattern)",
                    matchedRule: pattern
                )
            }
        }

        // 2. Allowlist by tool name.
        if rules.allowToolNames.contains(where: { $0.caseInsensitiveCompare(context.toolName) == .orderedSame }) {
            return AutoApproveDecision(
                behavior: .allow,
                reason: "tool '\(context.toolName)' in allowlist",
                matchedRule: context.toolName
            )
        }

        // 3. Allowlist by command prefix — but never for a chained command.
        if let command = context.command {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.hasShellChaining(trimmed) {
                let lowered = trimmed.lowercased()
                for pattern in rules.allowCommandPatterns where lowered.hasPrefix(pattern.lowercased()) {
                    return AutoApproveDecision(
                        behavior: .allow,
                        reason: "command matched allow rule: \(pattern)",
                        matchedRule: pattern
                    )
                }
            }
        }

        // 4. Nothing matched — fall back to the configured default.
        return AutoApproveDecision(behavior: rules.defaultBehavior, reason: "no rule matched")
    }
}
