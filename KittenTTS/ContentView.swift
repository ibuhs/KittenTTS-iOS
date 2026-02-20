//
//  ContentView.swift
//  KittenTTS
//
//  Created by Jin on 2026-02-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = KittenTTSEngine()
    @State private var inputText = "Hello, this is Kitten TTS running on iOS!"
    @State private var selectedVoice = "Jasper"
    @State private var selectedModel: KittenModel = .nano
    @State private var speed: Float = 1.0
    @State private var generatedAudio: [Float]?
    @State private var statusMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(engine.isLoaded ? Color.green : (engine.isLoadingModel ? Color.orange : Color.red))
                        .frame(width: 12, height: 12)
                    if engine.isLoadingModel {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(engine.isLoaded ? engine.loadedModelName : "Not Loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Model selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.headline)
                    
                    Picker("Model", selection: $selectedModel) {
                        ForEach(KittenModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedModel) { _, newModel in
                        generatedAudio = nil
                        engine.loadModel(newModel)
                    }
                }
                
                // Text input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text to speak")
                        .font(.headline)
                    
                    TextEditor(text: $inputText)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Voice selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Voice")
                            .font(.headline)
                        Spacer()
                        Text(selectedVoice)
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(KittenTTSEngine.availableVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
                
                // Speed slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1fx", speed))
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                }
                
                Spacer()
                
                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Error message
                if let error = engine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                
                // Generate button
                Button {
                    Task {
                        await generateSpeech()
                    }
                } label: {
                    HStack {
                        if engine.isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "waveform")
                        }
                        Text(engine.isGenerating ? "Generating..." : "Generate Speech")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(engine.isLoaded && !engine.isGenerating ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!engine.isLoaded || engine.isGenerating || inputText.isEmpty)
                
                // Play button (shown after generation)
                if generatedAudio != nil {
                    Button {
                        Task {
                            await playAudio()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Audio")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("🐱 Kitten TTS")
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private func generateSpeech() async {
        statusMessage = "Generating..."
        generatedAudio = nil
        
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let audio = try await engine.generate(text: inputText, voice: selectedVoice, speed: speed)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            generatedAudio = audio
            let audioDuration = Float(audio.count) / Float(KittenTTSEngine.sampleRate)
            statusMessage = String(format: "Generated %.1fs audio in %.2fs", audioDuration, duration)
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    private func playAudio() async {
        guard let audio = generatedAudio else { return }
        
        do {
            try await engine.playAudio(samples: audio)
            statusMessage = "Playing audio..."
        } catch {
            statusMessage = "Playback error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
