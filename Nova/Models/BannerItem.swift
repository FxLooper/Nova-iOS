import Foundation

// MARK: - Banner Item Model
// Univerzální model pro notification bannery

struct BannerItem: Identifiable, Equatable {
    let id = UUID()
    let type: BannerType
    let title: String
    let detail: String?
    let autoDismiss: TimeInterval? // nil = manuální dismiss

    enum BannerType: Equatable {
        case info       // šedý — obecné info
        case success    // zelený — hotovo, ready
        case warning    // oranžový — pozor
        case error      // červený — chyba, offline
        case dev        // modrý — dev mode
        case web        // zelený — web search
        case cron       // fialový — cron task
        case reminder   // žlutý — připomínka
    }

    static func == (lhs: BannerItem, rhs: BannerItem) -> Bool {
        lhs.id == rhs.id
    }
}
