//
//  KittenTTSEngine.swift
//  KittenTTS
//
//  ONNX Runtime based Text-to-Speech engine
//

import Foundation
import AVFoundation
import Combine
import onnxruntime_objc
import MisakiSwift

enum KittenModel: String, CaseIterable {
    case nano = "nano"
    case micro = "micro"
    case mini = "mini"
    
    var displayName: String {
        switch self {
        case .nano: return "Nano (15M)"
        case .micro: return "Micro (40M)"
        case .mini: return "Mini (80M)"
        }
    }
    
    var modelFileName: String {
        switch self {
        case .nano: return "kitten_tts_nano_v0_8"
        case .micro: return "kitten_tts_micro_v0_8"
        case .mini: return "kitten_tts_mini_v0_8"
        }
    }
}

@MainActor
class KittenTTSEngine: ObservableObject {
    
    private var session: ORTSession?
    private var env: ORTEnv?
    private var voiceEmbeddings: [String: [[Float]]] = [:]  // [voice: [400 positions x 256 dims]]
    private var g2p: EnglishG2P?
    private var currentModel: KittenModel = .nano
    
    @Published var isLoaded = false
    @Published var isGenerating = false
    @Published var isLoadingModel = false
    @Published var errorMessage: String?
    @Published var loadedModelName: String = ""
    
    static let sampleRate: Int = 24000
    static let availableVoices = ["Bella", "Jasper", "Luna", "Bruno", "Rosie", "Hugo", "Kiki", "Leo"]
    static let availableModels = KittenModel.allCases
    
    private var audioPlayer: AVAudioPlayer?
    
    enum KittenTTSError: Error, LocalizedError {
        case modelNotFound
        case sessionCreationFailed(String)
        case inferenceError(String)
        case voiceNotFound(String)
        case audioError(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "ONNX model file not found in bundle"
            case .sessionCreationFailed(let msg):
                return "Failed to create ONNX session: \(msg)"
            case .inferenceError(let msg):
                return "Inference error: \(msg)"
            case .voiceNotFound(let voice):
                return "Voice '\(voice)' not found"
            case .audioError(let msg):
                return "Audio error: \(msg)"
            }
        }
    }
    
    init() {
        loadModel(.nano)
    }
    
    func loadModel(_ model: KittenModel) {
        currentModel = model
        isLoadingModel = true
        isLoaded = false
        // Run model loading on background thread
        Task.detached { [weak self] in
            do {
                // Find model in bundle
                guard let modelPath = Bundle.main.path(forResource: model.modelFileName, ofType: "onnx") else {
                    await MainActor.run {
                        self?.errorMessage = "ONNX model '\(model.displayName)' not found in bundle"
                        self?.isLoadingModel = false
                    }
                    return
                }
                
                print("Loading model from: \(modelPath)")
                
                // Create ONNX Runtime environment
                let environment = try ORTEnv(loggingLevel: .warning)
                
                // Create session options
                let sessionOptions = try ORTSessionOptions()
                try sessionOptions.setLogSeverityLevel(.warning)
                try sessionOptions.setIntraOpNumThreads(2)
                
                // Create session
                let session = try ORTSession(
                    env: environment,
                    modelPath: modelPath,
                    sessionOptions: sessionOptions
                )
                
                // Load voice embeddings from JSON (model-specific)
                let voicesFileName = "voices_\(model.rawValue)"
                var voiceEmbeddings: [String: [[Float]]] = [:]
                if let voicesURL = Bundle.main.url(forResource: voicesFileName, withExtension: "json"),
                   let data = try? Data(contentsOf: voicesURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[Double]]] {
                    for (voice, embeddings) in json {
                        voiceEmbeddings[voice] = embeddings.map { $0.map { Float($0) } }
                    }
                    print("✅ Loaded voice embeddings for \(voiceEmbeddings.count) voices from \(voicesFileName).json")
                } else {
                    // Try generic voices.json as fallback
                    if let voicesURL = Bundle.main.url(forResource: "voices", withExtension: "json"),
                       let data = try? Data(contentsOf: voicesURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[Double]]] {
                        for (voice, embeddings) in json {
                            voiceEmbeddings[voice] = embeddings.map { $0.map { Float($0) } }
                        }
                        print("✅ Loaded voice embeddings for \(voiceEmbeddings.count) voices from voices.json")
                    } else {
                        print("⚠️ voices.json not found, using default embeddings")
                        for voice in KittenTTSEngine.availableVoices {
                            var positions: [[Float]] = []
                            for pos in 0..<400 {
                                var embedding = [Float](repeating: 0, count: 256)
                                let seed = voice.utf8.reduce(0) { $0 + Int($1) } + pos
                                for i in 0..<256 {
                                    embedding[i] = Float(sin(Double(i + seed) * 0.1)) * 0.1
                                }
                                positions.append(embedding)
                            }
                            voiceEmbeddings[voice] = positions
                        }
                    }
                }
                
                // Initialize MisakiSwift G2P (American English) - only once
                let g2p = EnglishG2P(british: false)
                
                // Update on main thread
                await MainActor.run {
                    self?.env = environment
                    self?.session = session
                    self?.voiceEmbeddings = voiceEmbeddings
                    self?.g2p = g2p
                    self?.isLoaded = true
                    self?.isLoadingModel = false
                    self?.loadedModelName = model.displayName
                    self?.errorMessage = nil
                    print("✅ Model \(model.displayName) loaded successfully!")
                }
                
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoadingModel = false
                    print("Error loading model: \(error)")
                }
            }
        }
    }
    
    // This function is no longer used - voice embeddings are loaded in loadModel()
    
    func generate(text: String, voice: String = "Jasper", speed: Float = 1.0) async throws -> [Float] {
        guard let session = session else {
            throw KittenTTSError.modelNotFound
        }
        
        guard let voicePositions = voiceEmbeddings[voice] else {
            throw KittenTTSError.voiceNotFound(voice)
        }
        
        // Select embedding based on text length (like Python: ref_id = min(len(text), shape[0] - 1))
        let refId = min(text.count, voicePositions.count - 1)
        let styleEmbedding = voicePositions[refId]
        print("🎤 Voice: \(voice), embedding position: \(refId), first 3 values: \(styleEmbedding.prefix(3))")
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("Generating speech for: \"\(text)\" with voice: \(voice)")
        
        // Tokenize text (character-level for now)
        let tokens = tokenize(text: text)
        print("Tokens: \(tokens.count)")
        
        // Create input tensors
        // Input 1: input_ids [1, seq_len] - INT64
        let inputIdsShape: [NSNumber] = [1, NSNumber(value: tokens.count)]
        let inputIdsData = tokens.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        let inputIdsTensor = try ORTValue(
            tensorData: NSMutableData(data: inputIdsData),
            elementType: .int64,
            shape: inputIdsShape
        )
        
        // Input 2: style [1, 256] - FLOAT
        let styleShape: [NSNumber] = [1, 256]
        let styleData = styleEmbedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        let styleTensor = try ORTValue(
            tensorData: NSMutableData(data: styleData),
            elementType: .float,
            shape: styleShape
        )
        
        // Input 3: speed [1] - FLOAT
        let speedShape: [NSNumber] = [1]
        var speedValue = speed
        let speedData = Data(bytes: &speedValue, count: MemoryLayout<Float>.size)
        
        let speedTensor = try ORTValue(
            tensorData: NSMutableData(data: speedData),
            elementType: .float,
            shape: speedShape
        )
        
        // Run inference
        print("Running inference...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let outputs = try session.run(
            withInputs: [
                "input_ids": inputIdsTensor,
                "style": styleTensor,
                "speed": speedTensor
            ],
            outputNames: ["waveform"],
            runOptions: nil
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print("Inference completed in \(String(format: "%.2f", (endTime - startTime) * 1000))ms")
        
        // Extract audio output
        guard let waveformOutput = outputs["waveform"] else {
            throw KittenTTSError.inferenceError("No waveform output")
        }
        
        let waveformData = try waveformOutput.tensorData() as Data
        let sampleCount = waveformData.count / MemoryLayout<Float>.size
        
        var audioSamples = [Float](repeating: 0, count: sampleCount)
        waveformData.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            for i in 0..<sampleCount {
                audioSamples[i] = floatBuffer[i]
            }
        }
        
        print("Generated \(audioSamples.count) samples (\(String(format: "%.2f", Float(audioSamples.count) / Float(Self.sampleRate)))s)")
        
        return audioSamples
    }
    
    // Preprocess text to expand acronyms and fix common pronunciation issues
    private func preprocessText(_ text: String) -> String {
        var processed = text
        
        // Common tech acronyms - expand to pronunciation-friendly form
        let acronyms: [String: String] = [
            "iOS": "eye oh ess",
            "macOS": "mac oh ess",
            "iPadOS": "eye pad oh ess",
            "watchOS": "watch oh ess",
            "tvOS": "tv oh ess",
            "visionOS": "vision oh ess",
            "API": "A P I",
            "APIs": "A P I s",
            "URL": "U R L",
            "URLs": "U R L s",
            "HTML": "H T M L",
            "CSS": "C S S",
            "JSON": "jason",
            "XML": "X M L",
            "SQL": "sequel",
            "GPU": "G P U",
            "CPU": "C P U",
            "RAM": "ram",
            "ROM": "rom",
            "USB": "U S B",
            "HDMI": "H D M I",
            "WiFi": "why fye",
            "AI": "A I",
            "ML": "M L",
            "NLP": "N L P",
            "LLM": "L L M",
            "GPT": "G P T",
            "TTS": "T T S",
            "STT": "S T T",
            "ASR": "A S R",
            "ONNX": "on ex",
            "SDK": "S D K",
            "IDE": "I D E",
            "UI": "U I",
            "UX": "U X",
            "OK": "okay",
            "vs": "versus",
            "etc": "etcetera",
        ]
        
        for (acronym, expansion) in acronyms {
            // Case-sensitive replacement
            processed = processed.replacingOccurrences(of: acronym, with: expansion)
        }
        
        return processed
    }
    
    private func tokenize(text: String) -> [Int64] {
        // Use MisakiSwift for phonemization
        guard let g2p = g2p else {
            print("G2P not initialized, falling back to simple tokenization")
            return simpleTokenize(text)
        }
        
        // Ensure text ends with punctuation (like Python ensure_punctuation)
        var processedText = preprocessText(text).trimmingCharacters(in: .whitespaces)
        if !processedText.isEmpty && !".!?,;:".contains(processedText.last!) {
            processedText += ","
        }
        
        // Convert text to phonemes using MisakiSwift
        let (phonemes, _) = g2p.phonemize(text: processedText)
        
        // Apply basic_english_tokenize: split on word boundaries, rejoin with spaces
        // This matches Python: phonemes = ' '.join(re.findall(r"\w+|[^\w\s]", phonemes))
        let tokenized = basicEnglishTokenize(phonemes)
        print("Phonemes: \(tokenized)")
        
        // Convert phonemes to token IDs using Kokoro-style vocabulary
        let tokens = phonemesToTokens(tokenized)
        
        // Pad with start/end tokens
        return [0] + tokens + [0]
    }
    
    // Matches Python: re.findall(r"\w+|[^\w\s]", text) then ' '.join()
    private func basicEnglishTokenize(_ text: String) -> String {
        var tokens: [String] = []
        var currentWord = ""
        
        for char in text {
            if char.isLetter || char.isNumber || char == "_" {
                currentWord.append(char)
            } else if !char.isWhitespace {
                // Punctuation or special char
                if !currentWord.isEmpty {
                    tokens.append(currentWord)
                    currentWord = ""
                }
                tokens.append(String(char))
            } else {
                // Whitespace
                if !currentWord.isEmpty {
                    tokens.append(currentWord)
                    currentWord = ""
                }
            }
        }
        if !currentWord.isEmpty {
            tokens.append(currentWord)
        }
        
        return tokens.joined(separator: " ")
    }
    
    private func simpleTokenize(_ text: String) -> [Int64] {
        // Fallback: simple character mapping
        return [0] + text.unicodeScalars.map { Int64($0.value % 256) } + [0]
    }
    
    // KittenTTS vocabulary - EXACT order from Python TextCleaner
    // _pad = "$", _punctuation = ';:,.!?¡¿—…"«»"" ', _letters, _letters_ipa
    private static let kittenVocab: [Character: Int64] = {
        let pad = "$"
        let punctuation = ";:,.!?¡¿—…\"«»\"\" "
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        let lettersIPA = "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘'̩'ᵻ"
        
        var symbols: [Character] = []
        symbols.append(contentsOf: pad)
        symbols.append(contentsOf: punctuation)
        symbols.append(contentsOf: letters)
        symbols.append(contentsOf: lettersIPA)
        
        var vocab: [Character: Int64] = [:]
        for (index, char) in symbols.enumerated() {
            vocab[char] = Int64(index)
        }
        return vocab
    }()
    
    private func phonemesToTokens(_ phonemes: String) -> [Int64] {
        var tokens: [Int64] = []
        var unknownChars: [Character] = []
        for char in phonemes {
            if let token = Self.kittenVocab[char] {
                tokens.append(token)
            } else {
                unknownChars.append(char)
            }
        }
        if !unknownChars.isEmpty {
            print("⚠️ Unknown characters not in vocab: \(unknownChars.map { String($0) }.joined(separator: ", "))")
        }
        print("📊 Token IDs: \(tokens.prefix(20))... (total: \(tokens.count))")
        return tokens
    }
    
    func playAudio(samples: [Float]) async throws {
        // Check if we have audio to play
        guard !samples.isEmpty else {
            throw KittenTTSError.audioError("No audio samples to play")
        }
        
        print("Playing \(samples.count) samples...")
        
        // Convert to Int16 PCM
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }
        
        // Create WAV data
        let wavData = createWAVData(samples: int16Samples)
        
        print("WAV data size: \(wavData.count) bytes")
        
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
            throw KittenTTSError.audioError("Audio session error: \(error.localizedDescription)")
        }
        
        // Play audio
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            let success = audioPlayer?.play() ?? false
            print("Audio playback started: \(success)")
        } catch {
            print("AVAudioPlayer error: \(error)")
            throw KittenTTSError.audioError(error.localizedDescription)
        }
    }
    
    private func createWAVData(samples: [Int16]) -> Data {
        var data = Data()
        
        let sampleRate: UInt32 = UInt32(Self.sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign: UInt16 = numChannels * bitsPerSample / 8
        let dataSize: UInt32 = UInt32(samples.count * 2)
        let fileSize: UInt32 = 36 + dataSize
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        return data
    }
    
    func stopAudio() {
        audioPlayer?.stop()
    }
}
