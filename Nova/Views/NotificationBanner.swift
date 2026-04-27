import SwiftUI

// MARK: - Nova Notification Banner
// Univerzální vyjížděcí banner pro různé stavy a upozornění

struct NotificationBanner: View {
    let banner: BannerItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                if let detail = banner.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(accentColor.opacity(0.06))
        .overlay(
            Rectangle()
                .fill(accentColor.opacity(0.3))
                .frame(width: 3),
            alignment: .leading
        )
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var iconName: String {
        switch banner.type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "wifi.slash"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .web: return "globe"
        case .cron: return "clock.arrow.circlepath"
        case .reminder: return "bell"
        }
    }

    private var accentColor: Color {
        switch banner.type {
        case .info: return Color(hex: "1a1a2e")
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .dev: return .blue
        case .web: return .green
        case .cron: return .purple
        case .reminder: return .yellow
        }
    }
}
