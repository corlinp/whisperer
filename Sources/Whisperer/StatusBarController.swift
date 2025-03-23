import SwiftUI
import AVFoundation

class StatusBarController: ObservableObject {
    @Published var isMenuOpen = false
    @Published var isRecording = false
    @Published var lastTranscribedText = ""
    
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let textInjector = TextInjector()
    
    // Status icons
    private let idleIcon = "waveform"
    private let recordingIcon = "waveform.circle.fill"
    
    init() {
        setupKeyMonitor()
        setupAudioRecorder()
        setupTranscriptionService()
    }
    
    private func setupKeyMonitor() {
        keyMonitor.onRightOptionKeyDown = { [weak self] in
            guard let self = self else { return }
            self.startRecording()
        }
        
        keyMonitor.onRightOptionKeyUp = { [weak self] in
            guard let self = self else { return }
            self.stopRecording()
        }
        
        // Start monitoring keys
        keyMonitor.start()
    }
    
    private func setupAudioRecorder() {
        audioRecorder.onAudioBufferCaptured = { [weak self] buffer in
            guard let self = self else { return }
            self.transcriptionService.sendAudioBuffer(buffer)
        }
    }
    
    private func setupTranscriptionService() {
        transcriptionService.onTranscriptionReceived = { [weak self] text in
            guard let self = self else { return }
            self.lastTranscribedText = text
            self.textInjector.injectText(text)
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        
        // Connect to OpenAI transcription service
        transcriptionService.connect()
        
        // Start audio recording
        audioRecorder.startRecording()
        
        // Reset text injector
        textInjector.reset()
        
        // Play sound to indicate recording started
        NSSound.beep()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        // Stop audio recording
        audioRecorder.stopRecording()
        
        // Disconnect from transcription service
        transcriptionService.disconnect()
        
        // Play sound to indicate recording stopped
        NSSound.beep()
    }
    
    func getStatusIcon() -> String {
        return isRecording ? recordingIcon : idleIcon
    }
    
    deinit {
        keyMonitor.stop()
        stopRecording()
    }
} 