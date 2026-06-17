import Foundation

/// Persists the user's auto-approve rule set across launches.
///
/// Backed by `UserDefaults`, JSON-encoded under a single key. Tests inject a
/// throwaway suite so production preferences aren't touched. Mirrors the
/// pattern of ``AgentIntentStore``.
public final class AutoApproveStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The current rule set. Falls back to ``AutoApproveRules/default`` when
    /// unset or unreadable, so a corrupt value never disables the feature
    /// silently or crashes the bridge.
    public var rules: AutoApproveRules {
        get {
            guard
                let data = defaults.data(forKey: Self.rulesKey),
                let decoded = try? JSONDecoder().decode(AutoApproveRules.self, from: data)
            else {
                return .default
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.rulesKey)
        }
    }

    /// Restore the built-in defaults.
    public func reset() {
        defaults.removeObject(forKey: Self.rulesKey)
    }

    // MARK: - Per-session pause

    /// 上限，防止 ID 集合无限增长（会话是临时的）。超出时丢弃最旧的。
    private static let maxPausedSessions = 500

    /// 已"暂停自动批准"的会话 ID（按加入顺序，最旧在前）。
    /// 用数组持久化以支持超限裁剪；对外按集合语义使用。
    private var pausedSessionIDs: [String] {
        get { defaults.stringArray(forKey: Self.pausedSessionsKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.pausedSessionsKey) }
    }

    /// 该会话是否已暂停自动批准（暂停=该会话的命令改为手动确认）。
    public func isAutoApprovePaused(forSession sessionID: String) -> Bool {
        pausedSessionIDs.contains(sessionID)
    }

    /// 设置某会话是否暂停自动批准。幂等。
    public func setAutoApprovePaused(_ paused: Bool, forSession sessionID: String) {
        var ids = pausedSessionIDs
        if paused {
            guard !ids.contains(sessionID) else { return }
            ids.append(sessionID)
            if ids.count > Self.maxPausedSessions {
                ids.removeFirst(ids.count - Self.maxPausedSessions)
            }
        } else {
            ids.removeAll { $0 == sessionID }
        }
        pausedSessionIDs = ids
    }

    /// 清除某会话的暂停标记（会话结束时调用，避免标记残留）。
    public func clearAutoApprovePause(forSession sessionID: String) {
        setAutoApprovePaused(false, forSession: sessionID)
    }

    private static let rulesKey = "autoApproveRules"
    private static let pausedSessionsKey = "autoApprovePausedSessions"
}
