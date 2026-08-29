import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var llmManager = LLMManager.shared
    @StateObject private var modelManager = ModelManager.shared
    
    @State private var temperature: Float = 0.7
    @State private var topP: Float = 0.9
    @State private var topK: Int = 40
    @State private var repetitionPenalty: Float = 1.1
    @State private var maxTokens: Int = 2048
    @State private var contextLength: Int = 4096
    @State private var systemPrompt: String = "You are a helpful AI assistant running locally on an iPhone."
    @State private var useFlashAttention: Bool = true
    
    @State private var showingModelConfig = false
    @State private var selectedModelConfig: ModelConfig?
    
    var body: some View {
        NavigationStack {
            Form {
                if let config = selectedModelConfig ?? llmManager.loadedModel {
                    Section("Model") {
                        HStack {
                            Text(config.name)
                            Spacer()
                            Text(config.quantization)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Section("Generation Parameters") {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Temperature")
                                Spacer()
                                Text(String(format: "%.2f", temperature))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $temperature, in: 0...2, step: 0.05)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Top-P")
                                Spacer()
                                Text(String(format: "%.2f", topP))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $topP, in: 0...1, step: 0.05)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Top-K")
                                Spacer()
                                Text("\(topK)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(topK) },
                                set: { topK = Int($0) }
                            ), in: 1...100, step: 1)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Repetition Penalty")
                                Spacer()
                                Text(String(format: "%.2f", repetitionPenalty))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $repetitionPenalty, in: 0.5...2.0, step: 0.05)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Max Tokens")
                                Spacer()
                                Text("\(maxTokens)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(maxTokens) },
                                set: { maxTokens = Int($0) }
                            ), in: 128...8192, step: 128)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Context Length")
                                Spacer()
                                Text("\(contextLength)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(contextLength) },
                                set: { contextLength = Int($0) }
                            ), in: 512...32768, step: 512)
                        }
                    }
                    
                    Section("Advanced") {
                        Toggle("Flash Attention", isOn: $useFlashAttention)
                            .help("Enable flash attention for faster inference on supported models")
                        
                        NavigationLink("System Prompt") {
                            SystemPromptEditor(prompt: $systemPrompt)
                        }
                    }
                    
                    Section("Memory") {
                        MemoryInfoView()
                    }
                    
                    Section("Actions") {
                        Button("Apply to Current Model") {
                            applySettings()
                        }
                        .disabled(llmManager.isLoading || llmManager.isGenerating)
                        
                        Button("Reset to Defaults") {
                            resetToDefaults()
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No Model Loaded",
                            systemImage: "cube.box",
                            description: Text("Load a model from the Models tab to configure settings")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }
    
    private func loadCurrentSettings() {
        if let config = selectedModelConfig ?? llmManager.loadedModel {
            temperature = config.temperature
            topP = config.topP
            topK = config.topK
            repetitionPenalty = config.repetitionPenalty
            maxTokens = config.maxTokens
            contextLength = config.contextLength
            systemPrompt = config.systemPrompt
            useFlashAttention = config.useFlashAttention
        }
    }
    
    private func applySettings() {
        guard var config = selectedModelConfig ?? llmManager.loadedModel else { return }
        
        config.temperature = temperature
        config.topP = topP
        config.topK = topK
        config.repetitionPenalty = repetitionPenalty
        config.maxTokens = maxTokens
        config.contextLength = contextLength
        config.systemPrompt = systemPrompt
        config.useFlashAttention = useFlashAttention
        
        try? config.modelContext?.save()
    }
    
    private func resetToDefaults() {
        temperature = 0.7
        topP = 0.9
        topK = 40
        repetitionPenalty = 1.1
        maxTokens = 2048
        contextLength = 4096
        systemPrompt = "You are a helpful AI assistant running locally on an iPhone."
        useFlashAttention = true
    }
}

struct SystemPromptEditor: View {
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("System Prompt") {
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 200)
            }
            
            Section("Presets") {
                ForEach(presets, id: \.0) { name, preset in
                    Button(name) {
                        prompt = preset
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("System Prompt")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
    
    private let presets = [
        ("Default", "You are a helpful AI assistant running locally on an iPhone."),
        ("Coding", "You are an expert programmer. Provide clean, efficient code with explanations."),
        ("Creative", "You are a creative writer. Be imaginative and engaging in your responses."),
        ("Concise", "You are a concise assistant. Give brief, direct answers without fluff."),
        ("Teacher", "You are a patient teacher. Explain concepts clearly with examples.")
    ]
}

struct MemoryInfoView: View {
    @StateObject private var llmManager = LLMManager.shared
    @State private var memoryInfo: (total: UInt64, used: UInt64, available: UInt64) = (0, 0, 0)
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryInfo.used), countStyle: .memory))
                        .font(.headline.monospaced())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryInfo.available), countStyle: .memory))
                        .font(.headline.monospaced())
                }
            }
            
            ProgressView(value: Double(memoryInfo.used), total: Double(memoryInfo.total))
                .tint(memoryColor)
            
            HStack {
                Text("Pressure: \(pressureText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if llmManager.memoryPressureLevel != .normal {
                    Label("High memory pressure - consider smaller model", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }
    
    private var memoryColor: Color {
        let percentage = Double(memoryInfo.used) / Double(memoryInfo.total)
        if percentage > 0.9 { return .red }
        if percentage > 0.75 { return .orange }
        return .green
    }
    
    private var pressureText: String {
        switch llmManager.memoryPressureLevel {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
    
    private func startMonitoring() {
        updateMemoryInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateMemoryInfo()
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateMemoryInfo() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let used = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        let total = ProcessInfo.processInfo.physicalMemory
        let available = total > used ? total - used : 0
        
        memoryInfo = (total, used, available)
    }
}