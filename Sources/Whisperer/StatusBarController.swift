import SwiftUI
import AVFoundation

class StatusBarController: ObservableObject {
    @Published var isMenuOpen = false
    @Published var isRecording = false
    @Published var lastTranscribedText = ""
    @Published var connectionState = "Disconnected"
    
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let textInjector = TextInjector()
    
    // Status icons
    private let idleIcon = "waveform"
    private let recordingIcon = "waveform.circle.fill"
    
    // Feedback sounds
    private let startSound = NSSound(named: "Pop")
    private let endSound = NSSound(named: "Blow")
    
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
            self.prepareToStopRecording()
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
        // Track connection state
        transcriptionService.onConnectionStateChanged = { [weak self] state in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch state {
                case .disconnected:
                    self.connectionState = "Disconnected"
                case .connecting:
                    self.connectionState = "Connecting"
                case .connected:
                    self.connectionState = "Connected"
                case .awaitingTranscription:
                    self.connectionState = "Finalizing"
                case .disconnecting:
                    self.connectionState = "Disconnecting"
                }
            }
        }
        
        // Track transcribed text
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
            
            // Inject the transcribed text to the active application
            self.textInjector.injectText(currentTranscribedText)
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        
        // Start audio recording immediately so no audio is missed
        audioRecorder.startRecording()
        
        // Reset text injector
        textInjector.reset()
        
        // Play sound to indicate recording started
        startSound?.play()
        
        // Connect to OpenAI transcription service
        // Audio captured during connection will be buffered and sent once connected
        transcriptionService.connect()
    }
    
    func prepareToStopRecording() {
        guard isRecording else { return }
        
        // Stop audio recording immediately
        audioRecorder.stopRecording()
        isRecording = false
        
        // Play sound to indicate recording stopped
        endSound?.play()
        
        // Tell transcription service to prepare for disconnect
        // This will keep the connection open until transcription is completed
        transcriptionService.prepareForDisconnect()
    }
    
    func getStatusIcon() -> String {
        return isRecording ? recordingIcon : idleIcon
    }
    
    deinit {
        keyMonitor.stop()
        
        if isRecording {
            audioRecorder.stopRecording()
        }
        
        transcriptionService.disconnect()
    }
} 