import SwiftUI

struct NovaBackground: View {
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                AnimatedMeshBackground()
            } else {
                Color(hex: "f5f0e8").ignoresSafeArea()
            }
        }
    }
}

@available(iOS 18.0, *)
private struct AnimatedMeshBackground: View {
    private let c1 = Color(hex: "f5f0e8")
    private let c2 = Color(hex: "ede6d6")
    private let c3 = Color(hex: "e4dcc8")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(elapsed: elapsed),
                colors: [c1, c2, c1, c2, c3, c2, c1, c2, c1]
            )
            .ignoresSafeArea()
        }
    }

    private func meshPoints(elapsed: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(elapsed * 0.35)) * 0.04
        let b = Float(cos(elapsed * 0.28)) * 0.03
        let c = Float(sin(elapsed * 0.22 + 1.2)) * 0.05
        return [
            SIMD2(0.0, 0.0),       SIMD2(0.5 + a, 0.0),       SIMD2(1.0, 0.0),
            SIMD2(0.0, 0.5 + b),   SIMD2(0.5 + c, 0.5 + a),   SIMD2(1.0, 0.5 + b),
            SIMD2(0.0, 1.0),       SIMD2(0.5 + c, 1.0),       SIMD2(1.0, 1.0)
        ]
    }
}
