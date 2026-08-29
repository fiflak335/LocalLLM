import SwiftUI
import SwiftData
import MarkdownUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var llmManager = LLMManager.shared
    @StateObject private var modelManager = ModelManager.shared
    
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var selectedSession: ChatSession?
    @State private var showingModelPicker = false
    @State private var showingSettings = false
    @State private var newMessage = ""
    @State private var isSidebarPresented = true
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(
                sessions: sessions,
                selectedSession: $selectedSession,
                onNewChat: createNewChat,
                onDeleteSession: deleteSession
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingModelPicker = true }) {
                        Label("Models", systemImage: "cube.box")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        } detail: {
            if let session = selectedSession {
                ChatDetailView(session: session)
            } else {
                EmptyStateView(onNewChat: createNewChat, onImportModel: { showingModelPicker = true })
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            modelManager.setModelContainer(modelContext.container)
            if selectedSession == nil, let first = sessions.first {
                selectedSession = first
            }
        }
    }
    
    private func createNewChat() {
        let config = modelManager.availableModels.first(where: { $0.isLoaded })
        let session = ChatSession(title: "New Chat", modelConfig: config)
        modelContext.insert(session)
        selectedSession = session
    }
    
    private func deleteSession(_ session: ChatSession) {
        modelContext.delete(session)
        if selectedSession?.id == session.id {
            selectedSession = sessions.first
        }
    }
}

struct SidebarView: View {
    let sessions: [ChatSession]
    @Binding var selectedSession: ChatSession?
    let onNewChat: () -> Void
    let onDeleteSession: (ChatSession) -> Void
    
    var body: some View {
        List(selection: $selectedSession) {
            Section {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            
            if !sessions.isEmpty {
                Section("History") {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            SessionRowView(session: session)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDeleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("LocalLLM")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Text("\(sessions.count) chats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SessionRowView: View {
    let session: ChatSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)
            if let lastMessage = session.messages.last {
                Text(lastMessage.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(session.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    let onNewChat: () -> Void
    let onImportModel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            
            Text("LocalLLM")
                .font(.largeTitle.bold())
            
            Text("Run LLMs locally on your iPhone")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                Button(action: onImportModel) {
                    Label("Import Model (.gguf)", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var session: ChatSession
    @StateObject private var llmManager = LLMManager.shared
    
    @State private var newMessage = ""
    @State private var isGenerating = false
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(spacing: 0) {
            if let modelConfig = session.modelConfig ?? llmManager.loadedModel {
                ModelInfoBar(config: modelConfig)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isGenerating {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom()
                }
                .onChange(of: isGenerating) { _, newValue in
                    if newValue {
                        scrollToBottom()
                    }
                }
            }
            
            if llmManager.isGenerating {
                GenerationStatsView(tokensPerSecond: llmManager.currentTokensPerSecond)
            }
            
            InputBar(
                text: $newMessage,
                isGenerating: llmManager.isGenerating,
                onSend: sendMessage,
                onStop: llmManager.stopGeneration
            )
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        modelContext.delete(session)
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !llmManager.isGenerating,
              let modelConfig = session.modelConfig ?? llmManager.loadedModel else { return }
        
        let userMessage = ChatMessage(role: .user, content: newMessage)
        session.messages.append(userMessage)
        session.updatedAt = Date()
        
        if session.title == "New Chat" {
            session.title = String(newMessage.prefix(50))
        }
        
        let currentMessage = newMessage
        newMessage = ""
        isGenerating = true
        
        llmManager.generateResponse(
            for: session.messages,
            config: modelConfig,
            onToken: { token in
                if let lastIndex = session.messages.lastIndex(where: { $0.role == .assistant }) {
                    session.messages[lastIndex].content += token
                } else {
                    let assistantMessage = ChatMessage(role: .assistant, content: token)
                    session.messages.append(assistantMessage)
                }
            },
            onComplete: { fullResponse, tokenCount, generationTime in
                if let lastIndex = session.messages.lastIndex(where: { $0.role == .assistant }) {
                    session.messages[lastIndex].tokenCount = tokenCount
                    session.messages[lastIndex].generationTime = generationTime
                }
                session.updatedAt = Date()
                isGenerating = false
            }
        )
    }
    
    private func scrollToBottom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if let lastMessage = session.messages.last {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            } else if isGenerating {
                scrollProxy?.scrollTo("typing", anchor: .bottom)
            }
        }
    }
}

struct ModelInfoBar: View {
    let config: ModelConfig
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.subheadline.weight(.medium))
                Text("\(config.architecture) • \(config.quantization) • \(config.parameterCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if config.isLoaded {
                Label("Loaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .user {
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Markdown(message.content)
                    .markdownTheme(.gitHub)
                    .markdownBlockConfiguration { config in
                        config.codeBlock = CodeBlockConfiguration()
                    }
                    .textSelection(.enabled)
                
                if message.role == .assistant, let tokens = message.tokenCount, let time = message.generationTime {
                    HStack(spacing: 8) {
                        Label("\(tokens) tokens", systemImage: "textformat.alt")
                        Label(String(format: "%.1f tok/s", Double(tokens) / time), systemImage: "speedometer")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
                    .frame(width: 32, height: 32)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: animating)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary, in: .rect(cornerRadius: 16))
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct GenerationStatsView: View {
    let tokensPerSecond: Double
    
    var body: some View {
        HStack {
            Spacer()
            Label(String(format: "%.1f tok/s", tokensPerSecond), systemImage: "speedometer")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary, in: .rect(cornerRadius: 8))
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(isGenerating)
                
                if isGenerating {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        .background(.regularMaterial)
    }
}

struct CodeBlockConfiguration: MarkdownCodeBlockConfiguration {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label?
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        
        ScrollView(.horizontal) {
            configuration.content
                .font(.system(.caption, design: .monospaced))
                .padding()
        }
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}