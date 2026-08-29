import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelConfig: ModelConfig?
    var messages: [ChatMessage]
    
    init(title: String = "New Chat", modelConfig: ModelConfig? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelConfig = modelConfig
        self.messages = []
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var tokenCount: Int
    var generationTime: Double?
    var session: ChatSession?
    
    init(role: MessageRole, content: String, tokenCount: Int = 0, generationTime: Double? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.tokenCount = tokenCount
        self.generationTime = generationTime
    }
}

enum MessageRole: String, Codable, CaseIterable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

@Model
final class ModelConfig {
    var id: UUID
    var name: String
    var filePath: String
    var fileSize: Int64
    var architecture: String
    var quantization: String
    var contextLength: Int
    var parameterCount: String
    var isLoaded: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    
    // Generation parameters
    var temperature: Float
    var topP: Float
    var topK: Int
    var repetitionPenalty: Float
    var maxTokens: Int
    var systemPrompt: String
    var useFlashAttention: Bool
    
    init(
        name: String,
        filePath: String,
        fileSize: Int64,
        architecture: String,
        quantization: String,
        contextLength: Int,
        parameterCount: String
    ) {
        self.id = UUID()
        self.name = name
        self.filePath = filePath
        self.fileSize = fileSize
        self.architecture = architecture
        self.quantization = quantization
        self.contextLength = contextLength
        self.parameterCount = parameterCount
        self.isLoaded = false
        self.createdAt = Date()
        
        // Default generation parameters
        self.temperature = 0.7
        self.topP = 0.9
        self.topK = 40
        self.repetitionPenalty = 1.1
        self.maxTokens = 2048
        self.systemPrompt = "You are a helpful AI assistant running locally on an iPhone."
        self.useFlashAttention = true
    }
}