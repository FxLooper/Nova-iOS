import AppIntents
import SwiftUI
import UIKit

// MARK: - Ask Nova Intent
// "Hey Siri, ask Nova what's the weather"
@available(iOS 16.0, *)
struct AskNovaIntent: AppIntent {
    static var title: LocalizedStringResource = "Zeptat se Novy"
    static var description = IntentDescription("Pošli Nově dotaz nebo příkaz hlasem.")

    // Když se spustí přes Siri, otevře appku na popředí (potřebujeme app pro audio + network)
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Dotaz",
        description: "Co se chceš Novy zeptat?",
        requestValueDialog: IntentDialog("Co mám Nově říct?")
    )
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Zeptat se Novy: \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Předáme query do appky přes deep link — NovaApp handler to chytne
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "nova://ask?q=\(encoded)") {
            await UIApplication.shared.open(url)
        }
        return .result(dialog: IntentDialog("Posílám Nově: \(query)"))
    }
}

// MARK: - Start Conversation Intent
// "Hey Siri, start Nova"
@available(iOS 16.0, *)
struct StartNovaConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Začít konverzaci s Novou"
    static var description = IntentDescription("Otevři Novu a spusť živou hlasovou konverzaci.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let url = URL(string: "nova://conversation") {
            await UIApplication.shared.open(url)
        }
        return .result(dialog: IntentDialog("Spouštím Novu"))
    }
}

// MARK: - Open Nova Intent
// "Hey Siri, open Nova"
@available(iOS 16.0, *)
struct OpenNovaIntent: AppIntent {
    static var title: LocalizedStringResource = "Otevřít Novu"
    static var description = IntentDescription("Otevři aplikaci Nova.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "nova://open") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider
// Zaregistruje Shortcuts automaticky do aplikace Shortcuts a Siri
@available(iOS 16.0, *)
struct NovaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskNovaIntent(),
            phrases: [
                "Zeptej se \(.applicationName)",
                "Řekni \(.applicationName)",
                "Ask \(.applicationName)",
                "Tell \(.applicationName)"
            ],
            shortTitle: "Zeptat se Novy",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
        AppShortcut(
            intent: StartNovaConversationIntent(),
            phrases: [
                // Primary wake phrases — user just says these in Siri ("Hey Siri, Hi Nova")
                "Hi \(.applicationName)",
                "Ahoj \(.applicationName)",
                "Hey \(.applicationName)",
                "Ok \(.applicationName)",
                // Legacy / longer forms
                "Začni s \(.applicationName)",
                "Spusť \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Konverzace s Novou",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: OpenNovaIntent(),
            phrases: [
                "Otevři \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Otevřít Novu",
            systemImageName: "sparkles"
        )
    }
}
