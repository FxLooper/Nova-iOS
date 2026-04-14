import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let role: String // "user" or "ai"
    let content: String
    let timestamp: Date
    let imageURL: String?

    init(role: String, content: String, imageURL: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.imageURL = imageURL
    }
}

struct ChatResponse: Codable {
    let content: String?
    let action: ActionResponse?
    let error: String?
}

struct ActionResponse: Codable {
    let action: String
    let params: [String: AnyCodable]?
    let speech: String?
}

// Helper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let dbl = try? container.decode(Double.self) { value = dbl }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let int = value as? Int { try container.encode(int) }
        else if let dbl = value as? Double { try container.encode(dbl) }
        else if let bool = value as? Bool { try container.encode(bool) }
    }
}
