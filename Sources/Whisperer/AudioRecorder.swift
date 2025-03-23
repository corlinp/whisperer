import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var isRecording = false
    
    // Buffer size for audio capture (samples)
    private let bufferSize: AVAudioFrameCount = 1024
    
    // Callback for when new audio buffer is captured
    var onAudioBufferCaptured: ((AVAudioPCMBuffer) -> Void)?
    
    override init() {
        super.init()
        setupAudioEngine()
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
                self.onAudioBufferCaptured?(convertedBuffer)
                self.audioBuffers.append(convertedBuffer)
            }
        }
    }
    
    private func convertBufferToFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Target format: 16kHz, 16-bit, mono for OpenAI transcription
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: true)
        
        guard let targetFormat = targetFormat,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            print("Failed to create audio converter")
            return nil
        }
        
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            print("Failed to create output buffer")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            print("Error converting audio: \(error.localizedDescription)")
            return nil
        }
        
        if status == .error {
            print("Error during audio conversion")
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
            print("Audio recording started")
        } catch {
            print("Failed to start audio recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        isRecording = false
        print("Audio recording stopped")
        
        // Reinstall tap for next recording
        setupAudioEngine()
    }
    
    // Convert the current audio buffer to 16-bit PCM data
    func getAudioData() -> Data? {
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
} 