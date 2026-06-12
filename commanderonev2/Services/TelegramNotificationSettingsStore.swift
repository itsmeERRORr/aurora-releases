import Foundation

struct TelegramNotificationSettings: Equatable {
    var isEnabled: Bool
    var chatID: String
    var botToken: String
    var hasSavedBotToken: Bool = false

    var isConfigured: Bool {
        isEnabled && !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUseSavedToken: Bool {
        isEnabled && !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasSavedBotToken || !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

enum TelegramNotificationSettingsStore {
    private static let enabledKey = "telegramDailySummaryEnabled"
    private static let chatIDKey = "telegramDailySummaryChatID"
    private static let hasTokenKey = "telegramDailySummaryHasBotToken"
    private static let keychainService = "errormedia.aurora.telegram"
    private static let tokenAccount = "botToken"

    static func load(includeToken: Bool = true) -> TelegramNotificationSettings {
        let hasSavedToken = UserDefaults.standard.bool(forKey: hasTokenKey)
        return TelegramNotificationSettings(
            isEnabled: UserDefaults.standard.bool(forKey: enabledKey),
            chatID: UserDefaults.standard.string(forKey: chatIDKey) ?? "",
            botToken: includeToken ? KeychainStore.string(service: keychainService, account: tokenAccount) ?? "" : "",
            hasSavedBotToken: hasSavedToken
        )
    }

    static func save(_ settings: TelegramNotificationSettings) {
        UserDefaults.standard.set(settings.isEnabled, forKey: enabledKey)
        UserDefaults.standard.set(settings.chatID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: chatIDKey)

        let token = settings.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            if !settings.hasSavedBotToken {
                KeychainStore.remove(service: keychainService, account: tokenAccount)
                UserDefaults.standard.set(false, forKey: hasTokenKey)
            }
        } else {
            KeychainStore.setString(token, service: keychainService, account: tokenAccount)
            UserDefaults.standard.set(true, forKey: hasTokenKey)
        }
    }
}
