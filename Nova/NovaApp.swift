import SwiftUI
import UserNotifications

@main
struct NovaApp: App {
    @StateObject private var novaService = NovaService()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(novaService)
                .environmentObject(novaService.voiceProfile)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "nova" else { return }
        let host = url.host ?? ""
        print("[deeplink] received \(url.absoluteString)")
        switch host {
        case "conversation", "open":
            // Tap na Dynamic Island / Live Activity / Siri Open → otevři konverzaci
            NotificationCenter.default.post(name: .openLiveConversation, object: nil)
        case "ask":
            // Siri AskNovaIntent → vytáhni query a pošli do chatu
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            if !query.isEmpty {
                NotificationCenter.default.post(
                    name: .siriAskNova,
                    object: nil,
                    userInfo: ["query": query]
                )
            }
        default:
            break
        }
    }
}

// AppDelegate pro notifikace — kliknutí na notifikaci otevře sheet s úkoly
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Request push notification permission + register for remote
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    // Device token received — send to server
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[push] device token: \(token)")
        // Store and send to server
        UserDefaults.standard.set(token, forKey: "nova_push_token")
        Task {
            await sendPushTokenToServer(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[push] registration failed: \(error.localizedDescription)")
    }

    private func sendPushTokenToServer(_ pushToken: String) async {
        guard let serverURL = KeychainHelper.load(key: "nova_server"),
              let novaToken = KeychainHelper.load(key: "nova_token"),
              let url = URL(string: "\(serverURL)/api/push/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(novaToken, forHTTPHeaderField: "X-Nova-Token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceToken": pushToken])
        _ = try? await URLSession.shared.data(for: request)
        print("[push] token sent to server")
    }

    // Notifikace přišla když je app v popředí — zobraz banner i tak
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Klepnutí na notifikaci → otevři ScheduledTasksView a rovnou detail daného úkolu
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let taskId = userInfo["taskId"] as? String, !taskId.isEmpty {
            // Ulož pending taskId — ScheduledTasksView ho po načtení otevře jako detail
            UserDefaults.standard.set(taskId, forKey: "pendingCronTaskId")
            print("[push] tap on notification, pending taskId=\(taskId)")
        }
        NotificationCenter.default.post(
            name: .openScheduledTasks,
            object: nil,
            userInfo: userInfo
        )
        completionHandler()
    }
}

extension Notification.Name {
    static let openScheduledTasks = Notification.Name("openScheduledTasks")
    static let openLiveConversation = Notification.Name("openLiveConversation")
    static let siriAskNova = Notification.Name("siriAskNova")
}
