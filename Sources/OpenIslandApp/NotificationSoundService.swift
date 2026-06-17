import AppKit

/// Manages notification sound playback. Supports macOS system sounds **and**
/// 紫微 自带的「星空」提示音（钢片琴·糖梅仙子琶音，真实录音，打包在 app 资源里）。
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"

    /// 紫微自带的星空提示音（显示名）与其资源文件名。
    static let starChimeName = "紫微 · 星空"
    private static let starChimeResource = "ziwei-star-chime"

    /// 默认就用自带星空音，而不是系统 Bottle。
    static let defaultSoundName = starChimeName

    /// 自带星空音的 NSSound（懒加载、缓存）。
    private static let starChimeSound: NSSound? = {
        guard let url = Bundle.appResources.url(
            forResource: starChimeResource,
            withExtension: "wav"
        ) else { return nil }
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.setName(NSSound.Name(starChimeName))
        return sound
    }()

    /// 可选声音列表：自带「紫微 · 星空」排第一，其后是系统声音。
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        let system = (try? fm.contentsOfDirectory(atPath: soundsDirectory))?
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted() ?? []
        return [starChimeName] + system
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a sound by name — 自带星空音走打包资源，其余走系统声音。
    static func play(_ name: String) {
        if name == starChimeName {
            guard let sound = starChimeSound else { return }
            sound.stop()
            sound.play()
            return
        }
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        sound.stop()
        sound.play()
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName)
    }
}
