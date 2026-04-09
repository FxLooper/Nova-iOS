import SwiftUI

// MARK: - Confirm Buttons (Ano/Ne pro akce)
struct ConfirmButtons: View {
    let yesLabel: String
    let noLabel: String
    let onConfirm: (Bool) -> Void

    @State private var responded = false
    @State private var choice: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                guard !responded else { return }
                responded = true
                choice = true
                onConfirm(true)
            }) {
                Text(yesLabel)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(1)
                    .foregroundColor(Color(hex: "f5f0e8"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(hex: "2a2a3a").opacity(choice == true ? 1 : (responded ? 0.3 : 0.85)))
                    .cornerRadius(24)
            }

            Button(action: {
                guard !responded else { return }
                responded = true
                choice = false
                onConfirm(false)
            }) {
                Text(noLabel)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(1)
                    .foregroundColor(Color(hex: "2a2a3a"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(hex: "e8e3db").opacity(choice == false ? 1 : (responded ? 0.3 : 1)))
                    .cornerRadius(24)
            }
        }
        .padding(.vertical, 8)
        .allowsHitTesting(!responded)
    }
}
