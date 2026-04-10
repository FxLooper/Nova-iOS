import SwiftUI

@main
struct NovaApp: App {
    @StateObject private var novaService = NovaService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(novaService)
                .environmentObject(novaService.voiceProfile)
                .preferredColorScheme(.light)
        }
    }
}
