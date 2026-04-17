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

    // Klepnutí na notifikaci → otevři ScheduledTasksView
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationCenter.default.post(name: .openScheduledTasks, object: nil)
        completionHandler()
    }
}

extension Notification.Name {
    static let openScheduledTasks = Notification.Name("openScheduledTasks")
}
