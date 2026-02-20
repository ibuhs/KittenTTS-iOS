# KittenTTS iOS

Native iOS implementation of [KittenTTS](https://github.com/KittenML/KittenTTS) using ONNX Runtime and [MisakiSwift](https://github.com/mlalma/MisakiSwift) for grapheme-to-phoneme conversion.

## Features

- 🐱 **Multiple Models**: Nano (15M), Micro (40M), Mini (80M)
- 🎤 **8 Voices**: Bella, Jasper, Luna, Bruno, Rosie, Hugo, Kiki, Leo
- ⚡ **Fast Inference**: ~300ms on iPhone for nano model
- 🔤 **Smart Phonemization**: MisakiSwift G2P with acronym expansion
- 📱 **Native SwiftUI**: Clean, modern interface

## Quick Start Checklist

- [ ] Clone repository
- [ ] Run `pod install`
- [ ] Copy model files from `models/` to Xcode bundle (or download from HuggingFace)
- [ ] Open `KittenTTS.xcworkspace`
- [ ] Build and run

## Requirements

- iOS 18.0+
- Xcode 16+
- CocoaPods

## Setup

### 1. Clone and Install Dependencies

```bash
git clone https://github.com/ibuhs/KittenTTS-iOS.git
cd KittenTTS-iOS
pod install
```

### 2. Add Model Files to Xcode

Model files are included in `models/` directory. Drag these into the KittenTTS folder in Xcode:

**Required (Nano - recommended):**
- `models/kitten_tts_nano_v0_8.onnx`
- `models/voices_nano.json`

**Optional (Micro/Mini):**
- `models/kitten_tts_micro_v0_8.onnx` + `models/voices_micro.json`
- `models/kitten_tts_mini_v0_8.onnx` + `models/voices_mini.json`

### 3. Build and Run

```bash
open KittenTTS.xcworkspace
```

## Model Comparison

| Model | Parameters | Size | Inference (iPhone) | Quality |
|-------|------------|------|-------------------|---------|
| **Nano** | 15M | 54MB | ~300ms | ⭐⭐⭐⭐⭐ Best |
| Micro | 40M | 40MB | ~1000ms | ⭐⭐⭐ Good |
| Mini | 80M | 75MB | ~1800ms | ⭐⭐⭐ Good |

> **Note**: The Nano model provides the best balance of speed and quality. Micro and Mini models may have pronunciation variations on some words.

## Known Issues

- [ ] **Micro/Mini pronunciation**: Larger models may have less stable pronunciation on certain words compared to Nano
- [ ] **Acronyms**: Some acronyms need manual expansion (iOS, TTS, API are handled automatically)

## Architecture

```
KittenTTS/
├── KittenTTSEngine.swift    # ONNX inference, audio playback
├── ContentView.swift        # SwiftUI interface
├── Packages/
│   ├── MisakiSwift-static/  # G2P phonemization
│   └── MLXUtilsLibrary-static/
└── Podfile                  # onnxruntime-objc dependency
```

## Phonemization

This project uses [MisakiSwift](https://github.com/mlalma/MisakiSwift) by [@mlalma](https://github.com/mlalma) for grapheme-to-phoneme (G2P) conversion. MisakiSwift is a Swift port of the [Misaki](https://github.com/hexgrad/misaki) G2P library, providing:

- Dictionary-based lookup for common words
- Neural network fallback (BART) for unknown words
- IPA phoneme output compatible with Kokoro/KittenTTS models

The phonemization pipeline:
1. Text preprocessing (acronym expansion)
2. MisakiSwift G2P conversion
3. Basic English tokenization (word boundary splitting)
4. Vocabulary mapping to token IDs

## Credits

- **[KittenTTS](https://github.com/KittenML/KittenTTS)** - Original TTS model by KittenML
- **[MisakiSwift](https://github.com/mlalma/MisakiSwift)** - Swift G2P phonemization by [@mlalma](https://github.com/mlalma)
- **[Misaki](https://github.com/hexgrad/misaki)** - Original Python G2P library
- **[ONNX Runtime](https://github.com/microsoft/onnxruntime)** - Cross-platform inference engine
- **[MLX](https://github.com/ml-explore/mlx-swift)** - Apple's ML framework (used by MisakiSwift)

## License

Apache 2.0
