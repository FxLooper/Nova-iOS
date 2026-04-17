import SwiftUI

// MARK: - Confirm Buttons (Ano/Ne pro akce)
struct ConfirmButtons: View {
    let yesLabel: String
    let noLabel: String
    let onConfirm: (Bool) -> Void

    @State private var responded = false
    @State private var choice: Bool?
    @State private var appear = false

    var body: some View {
        HStack(spacing: 14) {
            // YES button
            Button(action: {
                guard !responded else { return }
                HapticManager.shared.selectionChanged()
                withAnimation(.easeInOut(duration: 0.25)) {
                    responded = true
                    choice = true
                }
                onConfirm(true)
            }) {
                HStack(spacing: 8) {
                    if choice == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(yesLabel)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(1)
                }
                .foregroundColor(Color(hex: "f5f0e8"))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color(hex: "2a2a3a").opacity(choice == true ? 1 : (responded ? 0.15 : 0.85)))
                .cornerRadius(24)
                .scaleEffect(choice == true ? 1.02 : (responded ? 0.95 : 1))
            }

            // NO button
            Button(action: {
                guard !responded else { return }
                HapticManager.shared.selectionChanged()
                withAnimation(.easeInOut(duration: 0.25)) {
                    responded = true
                    choice = false
                }
                onConfirm(false)
            }) {
                HStack(spacing: 8) {
                    if choice == false {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(noLabel)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(1)
                }
                .foregroundColor(Color(hex: "2a2a3a").opacity(responded && choice != false ? 0.3 : 1))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color(hex: "e8e3db").opacity(choice == false ? 1 : (responded ? 0.15 : 1)))
                .cornerRadius(24)
                .scaleEffect(choice == false ? 1.02 : (responded ? 0.95 : 1))
            }
        }
        .padding(.vertical, 8)
        .allowsHitTesting(!responded)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                appear = true
            }
        }
    }
}
