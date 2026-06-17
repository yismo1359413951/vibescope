import Foundation
import Testing
@testable import OpenIslandCore

/// 按会话"暂停自动批准"的持久化逻辑（UserDefaults 后端）。
struct AutoApproveStoreTests {
    private func makeStore() -> AutoApproveStore {
        let suite = UserDefaults(suiteName: "AutoApproveStoreTests-\(UUID().uuidString)")!
        return AutoApproveStore(defaults: suite)
    }

    @Test
    func defaultsToNotPaused() {
        let store = makeStore()
        #expect(store.isAutoApprovePaused(forSession: "s1") == false)
    }

    @Test
    func setAndQueryPause() {
        let store = makeStore()
        store.setAutoApprovePaused(true, forSession: "s1")
        #expect(store.isAutoApprovePaused(forSession: "s1") == true)
        #expect(store.isAutoApprovePaused(forSession: "s2") == false)

        store.setAutoApprovePaused(false, forSession: "s1")
        #expect(store.isAutoApprovePaused(forSession: "s1") == false)
    }

    @Test
    func setPausedIsIdempotent() {
        let store = makeStore()
        store.setAutoApprovePaused(true, forSession: "s1")
        store.setAutoApprovePaused(true, forSession: "s1")
        #expect(store.isAutoApprovePaused(forSession: "s1") == true)
        // 关闭一次即彻底清除（不残留重复项）。
        store.setAutoApprovePaused(false, forSession: "s1")
        #expect(store.isAutoApprovePaused(forSession: "s1") == false)
    }

    @Test
    func clearPause() {
        let store = makeStore()
        store.setAutoApprovePaused(true, forSession: "s1")
        store.clearAutoApprovePause(forSession: "s1")
        #expect(store.isAutoApprovePaused(forSession: "s1") == false)
    }

    @Test
    func capsUnboundedGrowth() {
        let store = makeStore()
        // 远超上限(500)，最早的应被裁掉，最新的保留。
        for i in 0..<600 {
            store.setAutoApprovePaused(true, forSession: "s\(i)")
        }
        #expect(store.isAutoApprovePaused(forSession: "s599") == true)
        #expect(store.isAutoApprovePaused(forSession: "s0") == false)
    }
}
