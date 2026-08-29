import SwiftUI
import UniformTypeIdentifiers

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var llmManager = LLMManager.shared
    @State private var showingDocumentPicker = false
    @State private var showingDeleteAlert = false
    @State private var modelToDelete: ModelConfig?
    
    var body: some View {
        NavigationStack {
            List {
                if modelManager.availableModels.isEmpty {
                    ContentUnavailableView(
                        "No Models",
                        systemImage: "cube.box",
                        description: Text("Import a .gguf model file to get started")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section("Available Models") {
                        ForEach(modelManager.availableModels) { model in
                            ModelRowView(
                                model: model,
                                isLoaded: llmManager.loadedModel?.id == model.id,
                                isLoading: llmManager.isLoading,
                                onTap: { loadModel(model) },
                                onDelete: { modelToDelete = model; showingDeleteAlert = true }
                            )
                        }
                    }
                }
                
                Section {
                    Button(action: { showingDocumentPicker = true }) {
                        Label("Import .gguf Model", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(modelManager.isImporting)
                    
                    if modelManager.isImporting {
                        ProgressView(value: modelManager.importProgress) {
                            Text("Importing model...")
                        }
                    }
                }
                
                if modelManager.availableModels.isEmpty == false {
                    Section {
                        let freeSpace = modelManager.getAvailableSpace()
                        HStack {
                            Label("Free Space", systemImage: "internaldrive")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingDocumentPicker,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Delete Model", isPresented: $showingDeleteAlert, presenting: modelToDelete) { model in
                Button("Delete", role: .destructive) {
                    modelManager.deleteModel(model)
                }
                Button("Cancel", role: .cancel) {}
            } message: { model in
                Text("Are you sure you want to delete '\(model.name)'? This cannot be undone.")
            }
            .alert("Import Error", isPresented: .constant(modelManager.importError != nil), presenting: modelManager.importError) { _ in
                Button("OK") { modelManager.importError = nil }
            } message: { error in
                Text(error)
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await modelManager.importModel(from: url)
                }
            }
        case .failure(let error):
            modelManager.importError = error.localizedDescription
        }
    }
    
    private func loadModel(_ config: ModelConfig) {
        Task {
            do {
                try await llmManager.loadModel(config)
                modelManager.updateLastUsed(config)
            } catch {
                // Error handled in LLMManager
            }
        }
    }
}

struct ModelRowView: View {
    let model: ModelConfig
    let isLoaded: Bool
    let isLoading: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isLoaded ? "checkmark.circle.fill" : "cube.box")
                    .font(.title2)
                    .foregroundStyle(isLoaded ? .green : .blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        Label(model.architecture, systemImage: "cpu")
                        Label(model.quantization, systemImage: "chart.bar")
                        Label(model.parameterCount, systemImage: "number")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Label(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file), systemImage: "doc")
                        Label("Ctx: \(model.contextLength)", systemImage: "text.bubble")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if isLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}