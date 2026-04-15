import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var nova: NovaService
    @Environment(\.dismiss) var dismiss
    @State private var autoScroll = true
    @State private var showClearAlert = false

    // Kombinuj historii + aktuální live logy (deduplikace přes Set neuchová pořadí, jen append historie a pak live pokud nejsou v history)
    var logs: [String] {
        var combined = nova.devHistory
        // Přidej live logy které nejsou v history
        let historySet = Set(nova.devHistory)
        for live in nova.devLogs where !historySet.contains(live) {
            combined.append(live)
        }
        return combined
    }
    var isActive: Bool { nova.isDevMode }

    var body: some View {
        ZStack {
            // Tmavé pozadí (terminál look)
            Color(red: 0.08, green: 0.09, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    // macOS-style window dots
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 1.0, green: 0.4, blue: 0.4)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.3)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 0.4, green: 0.85, blue: 0.4)).frame(width: 11, height: 11)
                    }
                    Spacer()

                    Text("nova ~ dev terminal")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    // Live indikátor
                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.4))
                                .frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.85, blue: 0.4))
                        }
                    } else {
                        Text("IDLE")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.05, green: 0.06, blue: 0.08))

                Divider().background(Color.white.opacity(0.1))

                // Logs
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if logs.isEmpty {
                                Text("Žádné dev logy zatím. Pošli Nově dev příkaz.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.top, 40)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            ForEach(Array(logs.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(colorForLine(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                            // Anchor pro auto-scroll
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: logs.count) { _, _ in
                        if autoScroll {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Footer s počtem řádků + clear
                HStack {
                    Text("\(logs.count) lines")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    Spacer()

                    Button(action: { autoScroll.toggle() }) {
                        Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Button(action: { showClearAlert = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.05, green: 0.06, blue: 0.08))
            }
        }
        .onAppear {
            Task { await nova.loadDevHistory() }
        }
        .alert("Smazat historii?", isPresented: $showClearAlert) {
            Button("Smazat", role: .destructive) {
                Task { await nova.clearDevHistory() }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Vymaže všechny dev logy z terminálu. Tato akce nelze vrátit.")
        }
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("📖") { return Color(red: 0.5, green: 0.8, blue: 1.0) } // modrá - read
        if line.contains("✏️") || line.contains("📝") { return Color(red: 1.0, green: 0.8, blue: 0.4) } // oranžová - write
        if line.contains("$") { return Color(red: 0.6, green: 1.0, blue: 0.6) } // zelená - bash
        if line.contains("🚀") { return Color(red: 0.7, green: 0.7, blue: 1.0) } // fialová - start
        return .white.opacity(0.85)
    }
}
