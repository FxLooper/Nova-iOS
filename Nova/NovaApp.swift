import SwiftUI

@main
struct NovaApp: App {
    @StateObject private var novaService = NovaService()
    @StateObject private var voiceProfileService = VoiceProfileService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(novaService)
                .environmentObject(voiceProfileService)
                .preferredColorScheme(.light)
                .onAppear {
                    // Configure voice profile with server URL + token from Nova
                    voiceProfileService.configure(
                        serverURL: novaService.getServerURL(),
                        token: novaService.getToken()
                    )
                }
        }
    }
}
