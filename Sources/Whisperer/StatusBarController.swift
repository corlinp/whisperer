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
        var currentTranscribedText = ""
        
        transcriptionService.onTranscriptionReceived = { [weak self] text in
            guard let self = self else { return }
            
            // Check if this is a delta update or a full text update
            if text.count <= 2 || text.hasPrefix(" ") {
                // This is likely a delta - append to current text
                currentTranscribedText += text
                self.lastTranscribedText = currentTranscribedText
            } else if text.count < currentTranscribedText.count {
                // This appears to be a new utterance - replace the text
                currentTranscribedText = text
                self.lastTranscribedText = text
            } else {
                // This appears to be a complete text - use it directly
                currentTranscribedText = text
                self.lastTranscribedText = text
            }
            
            print("Current transcribed text: \"\(currentTranscribedText)\"")
            self.textInjector.injectText(currentTranscribedText)
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