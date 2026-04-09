import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nova: NovaService

    var body: some View {
        if nova.isConfigured {
            ChatView()
        } else {
            SetupView()
        }
    }
}

// MARK: - Setup View (first launch)
struct SetupView: View {
    @EnvironmentObject var nova: NovaService
    @State private var server = "http://192.168.0.183:3000"
    @State private var token = ""

    var body: some View {
        ZStack {
            Color(hex: "f5f0e8").ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                Text("nova")
                    .font(.system(size: 48, weight: .light))
                    .tracking(12)
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))

                Text("Připojení k serveru")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))

                VStack(spacing: 16) {
                    TextField("Server URL", text: $server)
                        .textFieldStyle(NovaTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    SecureField("API Token", text: $token)
                        .textFieldStyle(NovaTextFieldStyle())
                }
                .padding(.horizontal, 40)

                Button(action: {
                    nova.configure(server: server, token: token)
                }) {
                    Text("Připojit")
                        .font(.system(size: 15, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Color(hex: "f5f0e8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "1a1a2e").opacity(0.85))
                        .cornerRadius(999)
                }
                .padding(.horizontal, 40)
                .disabled(server.isEmpty || token.isEmpty)
                .opacity(server.isEmpty || token.isEmpty ? 0.4 : 1)

                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @EnvironmentObject var nova: NovaService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: "f5f0e8").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(nova.isConnected ? Color.green.opacity(0.6) : Color.red.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text("nova")
                        .font(.system(size: 18, weight: .light))
                        .tracking(6)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))

                    Spacer()

                    // State indicator
                    Text(stateLabel)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))

                    // Mute button
                    Button(action: { nova.toggleMute() }) {
                        Image(systemName: nova.isMuted ? "mic.slash" : "mic")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(hex: "f5f0e8").opacity(0.95))

                Divider().opacity(0.15)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(nova.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Interim speech text
                            if !nova.interimText.isEmpty {
                                HStack {
                                    Text(nova.interimText)
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                                        .italic()
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }

                            // Thinking indicator
                            if nova.state == .thinking {
                                HStack {
                                    ThinkingDots()
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: nova.messages.count) {
                        if let last = nova.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider().opacity(0.15)

                // Input bar
                HStack(spacing: 12) {
                    // Voice button
                    Button(action: {
                        if nova.state == .listening {
                            nova.stopListening()
                        } else {
                            nova.startListening()
                        }
                    }) {
                        Image(systemName: nova.state == .listening ? "waveform.circle.fill" : "waveform.circle")
                            .font(.system(size: 28))
                            .foregroundColor(nova.state == .listening
                                ? Color(hex: "1a1a2e").opacity(0.8)
                                : Color(hex: "1a1a2e").opacity(0.3))
                    }

                    TextField("Napiš Nově...", text: $inputText)
                        .font(.system(size: 15, weight: .light))
                        .focused($isInputFocused)
                        .onSubmit { sendText() }

                    Button(action: { sendText() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty
                                ? Color(hex: "1a1a2e").opacity(0.15)
                                : Color(hex: "1a1a2e").opacity(0.7))
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "f5f0e8").opacity(0.95))
            }
        }
        .onAppear {
            nova.connectWebSocket()
        }
    }

    private var stateLabel: String {
        switch nova.state {
        case .idle: return "Připravena"
        case .listening: return "Poslouchám..."
        case .thinking: return "Přemýšlím..."
        case .speaking: return "Mluvím..."
        }
    }

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        Task { await nova.sendMessage(text) }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.role == "user" ? "Ty" : "Nova")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))

                Text(message.content)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        message.role == "user"
                            ? Color(hex: "1a1a2e").opacity(0.06)
                            : Color(hex: "1a1a2e").opacity(0.03)
                    )
                    .cornerRadius(16)
                    .textSelection(.enabled)

                Text(timeString)
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.2))
            }

            if message.role != "user" { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: message.timestamp)
    }
}

// MARK: - Thinking Dots
struct ThinkingDots: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color(hex: "1a1a2e").opacity(i < dotCount ? 0.4 : 0.1))
                    .frame(width: 6, height: 6)
            }
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - Styles
struct NovaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15, weight: .light))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "1a1a2e").opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "1a1a2e").opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
