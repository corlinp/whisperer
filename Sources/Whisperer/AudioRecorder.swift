import Foundation
import AVFoundation

@MainActor
class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private let logEnabled = false
    
    // Buffer size for audio capture (samples)
    private let bufferSize: AVAudioFrameCount = 1024
    
    // Callback for when audio buffer has been completely captured
    var onRecordingComplete: ((Data) -> Void)?
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    deinit {
        // For deinit, we need to handle this in a way that doesn't capture self
        // Create local snapshot of variables needed
        let localIsRecording = isRecording
        let localInputNode = inputNode
        let localAudioEngine = audioEngine
        
        // Schedule cleanup on the main actor without capturing self
        if localIsRecording {
            Task.detached { @MainActor in
                // Stop the engine without using instance methods
                localAudioEngine?.stop()
                localInputNode?.removeTap(onBus: 0)
            }
        } else {
            // If not recording, we can do simple cleanup
            localInputNode?.removeTap(onBus: 0)
            localAudioEngine?.stop()
        }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // Use the input node's native format instead of forcing a specific format
        // This avoids format mismatch errors
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Install tap on input node with the native format
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self, self.isRecording else { return }
            
            // Convert to the format we need (16kHz, 16-bit, mono) for the transcription service
            if let convertedBuffer = self.convertBufferToFormat(buffer) {
                self.audioBuffers.append(convertedBuffer)
            }
        }
    }
    
    private func convertBufferToFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Target format: 16kHz, 16-bit, mono for OpenAI transcription
        // The API accepts flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, or webm
        // We'll use 16kHz, 16-bit, mono PCM which is compatible with their processing
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: true)
        
        guard let targetFormat = targetFormat,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            log("Failed to create audio converter")
            return nil
        }
        
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            log("Failed to create output buffer")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            log("Error converting audio: \(error.localizedDescription)")
            return nil
        }
        
        if status == .error {
            log("Error during audio conversion")
            return nil
        }
        
        return outputBuffer
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Clear previous buffers
        audioBuffers.removeAll()
        
        do {
            // Start audio engine
            try audioEngine.start()
            isRecording = true
            log("Audio recording started")
        } catch {
            log("Failed to start audio recording: \(error.localizedDescription)")
        }
    }
    
    // Regular MainActor method since we want to call it from the main actor context
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        isRecording = false
        
        log("Audio recording stopped")
        
        // Get the audio data and call the completion handler
        if let audioData = getAudioData() {
            onRecordingComplete?(audioData)
        } else {
            log("No audio data captured")
        }
        
        // Reinstall tap for next recording
        setupAudioEngine()
    }
    
    // Convert the current audio buffer to 16-bit PCM data
    private func getAudioData() -> Data? {
        guard !audioBuffers.isEmpty else { return nil }
        
        // Combine all audio buffers into one data object
        var combinedData = Data()
        
        for buffer in audioBuffers {
            guard let audioBuffer = buffer.int16ChannelData?[0] else { continue }
            
            let frameLength = Int(buffer.frameLength)
            let data = Data(bytes: audioBuffer, count: frameLength * 2) // 2 bytes per sample for Int16
            combinedData.append(data)
        }
        
        return combinedData
    }
    
    // Cancel recording without triggering the completion callback
    // Used for very short recordings we want to discard
    func cancelRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        isRecording = false
        
        log("Audio recording canceled (too short)")
        
        // Clear buffers
        audioBuffers.removeAll()
        
        // Reinstall tap for next recording
        setupAudioEngine()
    }
    
    private func log(_ message: String) {
        if logEnabled {
            print("[AudioRecorder] \(message)")
        }
    }
} 
