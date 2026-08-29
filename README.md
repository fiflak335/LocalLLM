# LocalLLM

Run Large Language Models locally on your iPhone with Metal GPU acceleration.

## Features

- 🤖 **Local Inference** - Runs entirely offline using MLX Swift with Metal acceleration
- 📁 **Model Import** - Load `.gguf` models (Llama, Qwen, Moondream) from Files app
- ⚙️ **Advanced Settings** - Temperature, Top-P, Top-K, Context Size, Repetition Penalty
- 💬 **Chat Interface** - Markdown rendering, code blocks, typing indicators
- 💾 **Persistent History** - SwiftData-powered chat sessions
- 🧠 **Memory Optimized** - Automatic KV cache management, memory pressure handling

## Requirements

- iOS 17.0+
- iPhone with A14 Bionic or later (recommended)
- Xcode 15.4+
- 2GB+ free storage for models

## Quick Start

### 1. Clone and Open in Xcode

```bash
git clone https://github.com/yourusername/LocalLLM.git
cd LocalLLM
open LocalLLM.xcodeproj
```

### 2. Build and Run

1. Select your development team in Signing & Capabilities
2. Build and run on device (simulator not supported for Metal)
3. Import a `.gguf` model from the Models tab
4. Start chatting!

### 3. Build IPA for Sideloading

```bash
# Ad-hoc (unsigned, for AltStore/Sideloadly)
./build_ipa.sh Release ad-hoc

# Signed (requires certificates)
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
export PROVISIONING_PROFILE_SPECIFIER="Your Profile"
./build_ipa.sh Release ad-hoc
```

## Supported Models

| Model | Size | Quantization | Performance |
|-------|------|--------------|-------------|
| Llama 3.2 1B | ~1.3 GB | Q4_K_M | ~30 tok/s |
| Llama 3.2 3B | ~3.8 GB | Q4_K_M | ~15 tok/s |
| Qwen 2.5 0.5B | ~0.7 GB | Q4_K_M | ~50 tok/s |
| Qwen 2.5 1.5B | ~1.8 GB | Q4_K_M | ~25 tok/s |
| Moondream 2 | ~1.8 GB | Q4_K_M | ~20 tok/s |

Download models from [Hugging Face](https://huggingface.co/models?search=gguf+mlx) or convert using `llama.cpp`.

## GitHub Actions CI/CD

The repository includes a workflow that automatically:
1. Builds the project on every tag push (`v*`)
2. Exports an unsigned IPA for sideloading
3. Creates a GitHub Release with the IPA attached

### To Release v1.0:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Manual Release:

1. Go to Actions → Build and Release IPA → Run workflow
2. Enter version (e.g., `1.0.0`)
3. Download IPA from workflow artifacts or Releases page

## Project Structure

```
LocalLLM/
├── Package.swift                    # Swift Package dependencies
├── build_ipa.sh                     # Local build script
├── .github/workflows/build-ipa.yml  # CI/CD pipeline
├── LocalLLM.xcodeproj/              # Xcode project
└── LocalLLM/
    ├── LocalLLMApp.swift            # App entry point
    ├── LocalLLM.entitlements        # App capabilities
    ├── Resources/Info.plist         # App configuration
    ├── Models/DataModels.swift      # SwiftData models
    ├── Views/
    │   ├── ContentView.swift        # Main chat UI
    │   ├── ModelPickerView.swift    # Model import/selection
    │   └── SettingsView.swift       # Generation parameters
    └── Services/
        ├── LLMManager.swift         # MLX inference engine
        └── ModelManager.swift       # Model file management
```

## Architecture

### Inference Engine (MLX Swift)
- Uses Apple's MLX framework for Metal-accelerated tensor operations
- `ModelContainer.performGeneration()` handles token streaming
- Flash Attention support for faster inference

### Memory Management
- GPU cache limited to 20MB
- KV cache cleared every 10 tokens during generation
- Memory pressure monitoring (normal/warning/critical)
- Automatic generation stop on critical pressure

### Model Format
- Supports GGUF files with MLX-compatible architectures
- Metadata extraction from GGUF header
- Automatic quantization detection

## Configuration

### Generation Parameters
| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Temperature | 0.0 - 2.0 | 0.7 | Randomness in sampling |
| Top-P | 0.0 - 1.0 | 0.9 | Nucleus sampling threshold |
| Top-K | 1 - 100 | 40 | Top-K sampling limit |
| Repetition Penalty | 0.5 - 2.0 | 1.1 | Penalize repeated tokens |
| Max Tokens | 128 - 8192 | 2048 | Maximum response length |
| Context Length | 512 - 32768 | 4096 | Model context window |

## Troubleshooting

### App Crashes on Model Load
- Try smaller model (1B-3B parameters)
- Ensure 2GB+ free storage
- Check memory pressure indicator in Settings

### Slow Generation
- Enable Flash Attention in Settings
- Reduce context length
- Use 4-bit quantized models

### Import Fails
- Ensure file has `.gguf` extension
- Try copying to Files app first
- Check model compatibility with MLX

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple's machine learning framework
- [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI) - Markdown rendering
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF format reference