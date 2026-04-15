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
        return true
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
