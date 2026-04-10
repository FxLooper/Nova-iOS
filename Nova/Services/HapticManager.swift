import UIKit

// MARK: - HapticManager
// Premium tactile feedback throughout Nova.
// Centralizovaná wrapper třída nad UIFeedbackGenerator API.
//
// Filozofie: subtle haptic na klíčové UX události — uživatel cítí appku, ne jen vidí.
// Inspirováno Face ID, Apple Pay, ProRAW shutter feedback.

@MainActor
class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        // Prewarm pro nulovou latenci při prvním použití
        lightImpact.prepare()
        mediumImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    // MARK: - Voice ID events

    /// Voice profile enrollment completed successfully.
    /// Notification success — distinct triple tap.
    func voiceEnrollmentSuccess() {
        notification.notificationOccurred(.success)
    }

    /// Voice profile enrollment failed (server error, audio too short).
    func voiceEnrollmentFailed() {
        notification.notificationOccurred(.error)
    }

    /// Voice verification succeeded — Nova recognized you.
    /// Light single tap (subtle confirmation).
    func voiceVerificationSuccess() {
        lightImpact.impactOccurred(intensity: 0.6)
    }

    /// Voice verification failed — unknown speaker.
    /// Warning notification (distinct double tap).
    func voiceVerificationFailed() {
        notification.notificationOccurred(.warning)
    }

    // MARK: - Conversation events

    /// User tapped orb to start/stop conversation.
    /// Medium impact — physical "switch flipped" feel.
    func conversationToggle() {
        mediumImpact.impactOccurred()
    }

    /// User started Push-to-Talk recording.
    /// Soft impact — gentle "recording armed" cue.
    func pushToTalkStart() {
        softImpact.impactOccurred(intensity: 0.7)
    }

    /// User released Push-to-Talk button.
    /// Light impact — confirmation that message was captured.
    func pushToTalkEnd() {
        lightImpact.impactOccurred()
    }

    /// Message sent to Nova (text or voice).
    /// Subtle selection feedback.
    func messageSent() {
        selection.selectionChanged()
    }

    /// Nova finished speaking response.
    /// Soft impact — "Nova is done" cue.
    func novaResponseComplete() {
        softImpact.impactOccurred(intensity: 0.4)
    }

    /// Confirmation button pressed (Yes/No in dev mode flow).
    func confirmationPressed() {
        rigidImpact.impactOccurred()
    }

    // MARK: - Generic

    /// UI selection change (e.g. settings toggle, picker).
    func selectionChanged() {
        selection.selectionChanged()
    }

    /// Critical error or warning.
    func errorOccurred() {
        notification.notificationOccurred(.error)
    }
}
