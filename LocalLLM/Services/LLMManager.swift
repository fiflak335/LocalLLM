import Foundation
import MLX
import MLXLLM
import MLXNN
import os.log

@MainActor
final class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    private let logger = Logger(subsystem: "com.localllm.app", category: "LLMManager")
    
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var currentTokensPerSecond: Double = 0
    @Published var loadedModel: ModelConfig?
    @Published var errorMessage: String?
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    
    private var modelContainer: ModelContainer?
    private var generationTask: Task<Void, Never>?
    private var kvCache: [KVCache]?
    private let memoryMonitor = MemoryMonitor()
    
    enum MemoryPressureLevel {
        case normal
        case warning
        case critical
    }
    
    private init() {
        setupMemoryMonitoring()
    }
    
    private func setupMemoryMonitoring() {
        memoryMonitor.onPressureChange = { [weak self] level in
            Task { @MainActor in
                self?.memoryPressureLevel = level
                if level == .critical {
                    self?.handleCriticalMemoryPressure()
                }
            }
        }
        memoryMonitor.start()
    }
    
    private func handleCriticalMemoryPressure() {
        logger.warning("Critical memory pressure - clearing KV cache")
        clearKVCache()
        if isGenerating {
            stopGeneration()
        }
    }
    
    func loadModel(_ config: ModelConfig) async throws {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let modelURL = URL(fileURLWithPath: config.filePath)
            
            let modelConfiguration = ModelConfiguration(
                id: config.name,
                tokenizerConfig: TokenizerConfig(
                    vocabularySize: 32000,
                    maxSequenceLength: config.contextLength
                ),
                modelConfig: ModelArchitectureConfig(
                    hiddenSize: 4096,
                    intermediateSize: 11008,
                    numHiddenLayers: 32,
                    numAttentionHeads: 32,
                    numKeyValueHeads: 32,
                    maxPositionEmbeddings: config.contextLength,
                    rmsNormEps: 1e-5,
                    ropeTheta: 10000.0,
                    vocabularySize: 32000
                ),
                quantization: config.quantization
            )
            
            modelContainer = try await ModelContainer.load(
                configuration: modelConfiguration,
                from: modelURL,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.logger.info("Loading model: \(progress.fractionCompleted * 100)%")
                    }
                }
            )
            
            loadedModel = config
            config.isLoaded = true
            logger.info("Model loaded successfully: \(config.name)")
            
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            logger.error("Model load failed: \(error)")
            throw error
        }
    }
    
    func generateResponse(
        for messages: [ChatMessage],
        config: ModelConfig,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String, Int, Double) -> Void
    ) {
        guard let modelContainer = modelContainer, !isGenerating else { return }
        
        isGenerating = true
        currentTokensPerSecond = 0
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var generatedTokens = 0
        var fullResponse = ""
        
        let generationConfig = GenerationConfiguration(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            topK: config.topK,
            repetitionPenalty: config.repetitionPenalty,
            useFlashAttention: config.useFlashAttention
        )
        
        let conversationHistory = messages.map { msg in
            ChatMessage(role: msg.role.rawValue, content: msg.content)
        }
        
        generationTask = Task {
            do {
                let stream = try await modelContainer.performGeneration(
                    messages: conversationHistory,
                    configuration: generationConfig
                )
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    generatedTokens += 1
                    fullResponse += chunk
                    
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    if elapsed > 0 {
                        currentTokensPerSecond = Double(generatedTokens) / elapsed
                    }
                    
                    onToken(chunk)
                    
                    if generatedTokens % 10 == 0 {
                        clearKVCacheIfNeeded()
                    }
                }
                
                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                onComplete(fullResponse, generatedTokens, totalTime)
                
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Generation failed: \(error.localizedDescription)"
                    logger.error("Generation error: \(error)")
                    onComplete("", 0, 0)
                }
            }
            
            isGenerating = false
            currentTokensPerSecond = 0
        }
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        currentTokensPerSecond = 0
    }
    
    private func clearKVCacheIfNeeded() {
        guard memoryPressureLevel != .normal else { return }
        clearKVCache()
    }
    
    private func clearKVCache() {
        kvCache?.removeAll()
        kvCache = nil
    }
    
    func unloadModel() {
        stopGeneration()
        modelContainer = nil
        loadedModel?.isLoaded = false
        loadedModel = nil
        clearKVCache()
        logger.info("Model unloaded")
    }
    
    deinit {
        memoryMonitor.stop()
    }
}

struct GenerationConfiguration {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let repetitionPenalty: Float
    let useFlashAttention: Bool
}

struct ChatMessage {
    let role: String
    let content: String
}

actor MemoryMonitor {
    var onPressureChange: ((LLMManager.MemoryPressureLevel) -> Void)?
    private var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkMemoryPressure() {
        let memoryInfo = getMemoryInfo()
        let usedPercentage = Double(memoryInfo.used) / Double(memoryInfo.total)
        
        let level: LLMManager.MemoryPressureLevel
        if usedPercentage > 0.9 {
            level = .critical
        } else if usedPercentage > 0.75 {
            level = .warning
        } else {
            level = .normal
        }
        
        onPressureChange?(level)
    }
    
    private func getMemoryInfo() -> (total: UInt64, used: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let used = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        let total = ProcessInfo.processInfo.physicalMemory
        
        return (total, used)
    }
}