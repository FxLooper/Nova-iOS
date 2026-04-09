import SwiftUI

// MARK: - Zen Orb Animation
struct OrbView: View {
    let state: NovaService.NovaState
    let audioLevel: CGFloat

    @State private var rotation: Double = 0
    @State private var breathe: CGFloat = 1.0
    @State private var particles: [OrbParticle] = OrbView.generateParticles(count: 60)
    @State private var rings: [OrbRing] = OrbView.generateRings()

    var body: some View {
        ZStack {
            // Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(breathe * 1.1)

            // Orbital rings
            ForEach(rings.indices, id: \.self) { i in
                Ellipse()
                    .stroke(Color(hex: "2a2a3a").opacity(rings[i].opacity), lineWidth: rings[i].width)
                    .frame(width: rings[i].rx * 2, height: rings[i].ry * 2)
                    .rotationEffect(.degrees(rings[i].angle + rotation * rings[i].speed))
            }

            // Particles
            ForEach(particles.indices, id: \.self) { i in
                Circle()
                    .fill(Color(hex: particles[i].color).opacity(particles[i].opacity))
                    .frame(width: particles[i].size, height: particles[i].size)
                    .offset(x: particles[i].x * breathe, y: particles[i].y * breathe)
                    .rotationEffect(.degrees(rotation * particles[i].speed))
            }

            // Core gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "7a7a9a").opacity(0.9),
                            Color(hex: "4a4a6a").opacity(0.7),
                            Color(hex: "2a2a3a").opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .scaleEffect(breathe)

            // Inner core
            Circle()
                .fill(Color(hex: "5a5a7a").opacity(0.8))
                .frame(width: 16, height: 16)
                .scaleEffect(1 + energyPulse * 0.3)

            // Bright center
            Circle()
                .fill(Color(hex: "8a8aaa").opacity(0.9))
                .frame(width: 6, height: 6)
                .scaleEffect(1 + energyPulse * 0.5)

            // State label
            VStack {
                Spacer()
                Text(stateLabel)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                    .tracking(2)
            }
            .frame(height: 200)
        }
        .frame(width: 200, height: 200)
        .onAppear { startAnimation() }
    }

    // MARK: - Animation
    private func startAnimation() {
        // Rotation
        withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        // Breathe
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            breathe = 1.04
        }
    }

    // MARK: - State-dependent properties
    private var accentColor: Color {
        switch state {
        case .idle: return Color(hex: "6a7a88")
        case .listening: return Color(hex: "8a5a3a")
        case .thinking: return Color(hex: "5a6a5a")
        case .speaking: return Color(hex: "3a5a6a")
        }
    }

    private var energyPulse: CGFloat {
        switch state {
        case .idle: return 0
        case .listening: return audioLevel
        case .thinking: return 0.5
        case .speaking: return audioLevel * 0.8
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle: return ""
        case .listening: return "POSLOUCHÁM"
        case .thinking: return "PŘEMÝŠLÍM"
        case .speaking: return "MLUVÍM"
        }
    }

    // MARK: - Particle generation
    struct OrbParticle {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let color: String
        let speed: Double
    }

    struct OrbRing {
        let rx: CGFloat
        let ry: CGFloat
        let angle: Double
        let opacity: Double
        let width: CGFloat
        let speed: Double
    }

    static func generateParticles(count: Int) -> [OrbParticle] {
        (0..<count).map { _ in
            let angle = Double.random(in: 0...360)
            let distance = CGFloat.random(in: 10...80)
            let rad = angle * .pi / 180
            return OrbParticle(
                x: cos(rad) * distance,
                y: sin(rad) * distance,
                size: CGFloat.random(in: 1...4),
                opacity: Double.random(in: 0.15...0.5),
                color: ["1a1a2e", "2a2a3a", "3a3a5a"].randomElement()!,
                speed: Double.random(in: 0.3...1.5)
            )
        }
    }

    static func generateRings() -> [OrbRing] {
        [
            OrbRing(rx: 55, ry: 20, angle: -25, opacity: 0.15, width: 0.6, speed: 0.3),
            OrbRing(rx: 65, ry: 28, angle: 30, opacity: 0.2, width: 0.8, speed: -0.2),
            OrbRing(rx: 48, ry: 16, angle: 55, opacity: 0.12, width: 0.5, speed: 0.5),
            OrbRing(rx: 72, ry: 22, angle: -15, opacity: 0.1, width: 0.4, speed: -0.4),
        ]
    }
}
