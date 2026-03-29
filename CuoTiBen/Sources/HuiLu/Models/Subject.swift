import Foundation

// MARK: - Subject Model
/// Represents a subject or project (e.g., 考研数学，IELTS, Nursing)
public struct Subject: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var examDate: Date?
    public var createdAt: Date
    
    public init(id: UUID = UUID(), name: String, examDate: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.examDate = examDate
        self.createdAt = createdAt
    }
}
