import Testing
import Foundation
@testable import iris

@Suite("Emoji settings")
struct EmojiSettingsTests {
    @Test("default skin tone persists to UserDefaults")
    func persists() {
        let key = "DEFAULT_EMOJI_SKIN_TONE"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let config = ConfigManager.shared
        config.defaultEmojiSkinTone = SkinTone.dark.rawValue
        #expect(UserDefaults.standard.integer(forKey: key) == 6)
    }

    @Test("ConfigManager.init() reads skin tone from UserDefaults")
    func readsBackOnInit() {
        let key = "DEFAULT_EMOJI_SKIN_TONE"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(SkinTone.dark.rawValue, forKey: key)
        let fresh = ConfigManager()
        #expect(fresh.defaultEmojiSkinTone == SkinTone.dark.rawValue)
    }
}
