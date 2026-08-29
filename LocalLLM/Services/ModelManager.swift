import Foundation
import UniformTypeIdentifiers
import SwiftData
import os.log

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    private let logger = Logger(subsystem: "com.localllm.app", category: "ModelManager")
    private let fileManager = FileManager.default
    
    @Published var availableModels: [ModelConfig] = []
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importError: String?
    
    private var modelContainer: ModelContainer?
    
    private init() {
        setupModelsDirectory()
        loadSavedModels()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    private func setupModelsDirectory() {
        let modelsURL = getModelsDirectory()
        if !fileManager.fileExists(atPath: modelsURL.path) {
            try? fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        }
    }
    
    func getModelsDirectory() -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Models")
    }
    
    func importModel(from url: URL) async {
        isImporting = true
        importProgress = 0
        importError = nil
        
        defer {
            isImporting = false
            importProgress = 1.0
        }
        
        do {
            let modelsDir = getModelsDirectory()
            let fileName = url.lastPathComponent
            let destinationURL = modelsDir.appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                let timestamp = DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let newName = "\(fileName.dropLast(5))_\(timestamp).gguf"
                try fileManager.copyItem(at: url, to: modelsDir.appendingPathComponent(newName))
            } else {
                try fileManager.copyItem(at: url, to: destinationURL)
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            let metadata = try extractModelMetadata(from: destinationURL)
            
            let config = ModelConfig(
                name: metadata.name ?? fileName.dropLast(5).description,
                filePath: destinationURL.path,
                fileSize: fileSize,
                architecture: metadata.architecture ?? "Unknown",
                quantization: metadata.quantization ?? "Unknown",
                contextLength: metadata.contextLength ?? 4096,
                parameterCount: metadata.parameterCount ?? "Unknown"
            )
            
            modelContainer?.mainContext.insert(config)
            try modelContainer?.mainContext.save()
            
            availableModels.append(config)
            logger.info("Model imported: \(config.name)")
            
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
            logger.error("Model import failed: \(error)")
        }
    }
    
    private func extractModelMetadata(from url: URL) throws -> (name: String?, architecture: String?, quantization: String?, contextLength: Int?, parameterCount: String?) {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        let headerData = try fileHandle.read(upToCount: 8192) ?? Data()
        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        
        var name: String?
        var architecture: String?
        var quantization: String?
        var contextLength: Int?
        var parameterCount: String?
        
        if let nameMatch = headerString.range(of: "general\\.name\\s*=\\s*\"([^\"]+)\"", options: .regularExpression) {
            name = String(headerString[nameMatch]).replacingOccurrences(of: "general.name = \"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        if let archMatch = headerString.range(of: "general\\.architecture\\s*=\\s*\"([^\"]+)\"", options: .regularExpression) {
            architecture = String(headerString[archMatch]).replacingOccurrences(of: "general.architecture = \"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        if let quantMatch = headerString.range(of: "general\\.quantization_version\\s*=\\s*\"([^\"]+)\"", options: .regularExpression) {
            quantization = String(headerString[quantMatch]).replacingOccurrences(of: "general.quantization_version = \"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        if let ctxMatch = headerString.range(of: "llama\\.context_length\\s*=\\s*(\\d+)", options: .regularExpression) {
            let value = String(headerString[ctxMatch]).replacingOccurrences(of: "llama.context_length = ", with: "")
            contextLength = Int(value)
        }
        
        if let paramMatch = headerString.range(of: "general\\.parameter_count\\s*=\\s*\"([^\"]+)\"", options: .regularExpression) {
            parameterCount = String(headerString[paramMatch]).replacingOccurrences(of: "general.parameter_count = \"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        return (name, architecture, quantization, contextLength, parameterCount)
    }
    
    private func loadSavedModels() {
        guard let container = modelContainer else { return }
        
        do {
            let descriptor = FetchDescriptor<ModelConfig>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
            availableModels = try container.mainContext.fetch(descriptor)
        } catch {
            logger.error("Failed to load saved models: \(error)")
        }
    }
    
    func deleteModel(_ config: ModelConfig) {
        do {
            try fileManager.removeItem(atPath: config.filePath)
            modelContainer?.mainContext.delete(config)
            try modelContainer?.mainContext.save()
            availableModels.removeAll { $0.id == config.id }
            logger.info("Model deleted: \(config.name)")
        } catch {
            logger.error("Failed to delete model: \(error)")
        }
    }
    
    func updateLastUsed(_ config: ModelConfig) {
        config.lastUsedAt = Date()
        try? modelContainer?.mainContext.save()
    }
    
    func getAvailableSpace() -> Int64 {
        let modelsDir = getModelsDirectory()
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: modelsDir.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}