# KittenTTS iOS

Native iOS implementation of [KittenTTS](https://github.com/KittenML/KittenTTS) using ONNX Runtime and MisakiSwift for phonemization.

## Features

- 🐱 **Multiple Models**: Nano (15M), Micro (40M), Mini (80M)
- 🎤 **8 Voices**: Bella, Jasper, Luna, Bruno, Rosie, Hugo, Kiki, Leo
- ⚡ **Fast Inference**: ~300ms on iPhone for nano model
- 🔤 **Smart Phonemization**: MisakiSwift G2P with acronym expansion
- 📱 **Native SwiftUI**: Clean, modern interface

## Requirements

- iOS 18.0+
- Xcode 16+
- CocoaPods

## Setup

### 1. Clone and Install Dependencies

```bash
git clone https://github.com/kailaDev/KittenTTS-iOS.git
cd KittenTTS-iOS
pod install
```

### 2. Download Model Files

Download from HuggingFace:

```bash
# Nano model (recommended - fastest)
curl -L -o kitten_tts_nano_v0_8.onnx "https://huggingface.co/KittenML/kitten-tts-nano-0.8/resolve/main/kitten_tts_nano_v0_8.onnx"
curl -L -o voices.npz "https://huggingface.co/KittenML/kitten-tts-nano-0.8/resolve/main/voices.npz"

# Optional: Micro model
curl -L -o kitten_tts_micro_v0_8.onnx "https://huggingface.co/KittenML/kitten-tts-micro-0.8/resolve/main/kitten_tts_micro_v0_8.onnx"

# Optional: Mini model  
curl -L -o kitten_tts_mini_v0_8.onnx "https://huggingface.co/KittenML/kitten-tts-mini-0.8/resolve/main/kitten_tts_mini_v0_8.onnx"
```

### 3. Convert Voice Embeddings to JSON

```python
import numpy as np, json

aliases = {
    'Bella': 'expr-voice-2-f', 'Jasper': 'expr-voice-2-m',
    'Luna': 'expr-voice-3-f', 'Bruno': 'expr-voice-3-m',
    'Rosie': 'expr-voice-4-f', 'Hugo': 'expr-voice-4-m',
    'Kiki': 'expr-voice-5-f', 'Leo': 'expr-voice-5-m'
}

v = np.load('voices.npz')
output = {name: v[internal].tolist() for name, internal in aliases.items()}
with open('voices_nano.json', 'w') as f:
    json.dump(output, f)
```

### 4. Add Files to Xcode Bundle

Drag these files into the KittenTTS folder in Xcode:
- `kitten_tts_nano_v0_8.onnx`
- `voices_nano.json`

### 5. Build and Run

```bash
open KittenTTS.xcworkspace
```

## Architecture

- **KittenTTSEngine.swift**: ONNX Runtime inference, audio playback
- **ContentView.swift**: SwiftUI interface  
- **MisakiSwift**: G2P phonemization (local static package)
- **onnxruntime-objc**: ONNX inference (CocoaPods)

## Credits

- [KittenTTS](https://github.com/KittenML/KittenTTS) - Original model by KittenML
- [MisakiSwift](https://github.com/mlalma/MisakiSwift) - G2P phonemization
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) - Inference engine

## License

MIT
