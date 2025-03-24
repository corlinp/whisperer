import SwiftUI
import AVFoundation

class StatusBarController: ObservableObject {
    @Published var isMenuOpen = false
    @Published var isRecording = false
    @Published var lastTranscribedText = ""
    @Published var transcriptionHistory: [String] = []
    @Published var connectionState = "Idle"
    
    // Maximum number of transcriptions to keep in history
    private let maxHistoryItems = 3
    
    // Current session's accumulating transcription text
    private var currentSessionText = ""
    
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
            self.stopRecording()
        }
        
        // Start monitoring keys
        keyMonitor.start()
    }
    
    private func setupAudioRecorder() {
        audioRecorder.onRecordingComplete = { [weak self] audioData in
            guard let self = self else { return }
            // Send the complete audio data for transcription
            self.transcriptionService.finishRecording(withAudioData: audioData)
        }
    }
    
    private func setupTranscriptionService() {
        // Track connection state
        transcriptionService.onConnectionStateChanged = { [weak self] state in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch state {
                case .idle:
                    self.connectionState = "Idle"
                case .recording:
                    self.connectionState = "Recording"
                case .transcribing:
                    self.connectionState = "Transcribing"
                case .error:
                    self.connectionState = "Error"
                }
            }
        }
        
        transcriptionService.onTranscriptionReceived = { [weak self] text in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Append the new text to the current session's text
                self.currentSessionText += text
                self.lastTranscribedText = self.currentSessionText
                
                // Inject the transcribed text delta to the active application
                self.textInjector.injectText(text)
            }
        }
        
        transcriptionService.onTranscriptionComplete = { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Only add to history if we have some text
                if !self.currentSessionText.isEmpty {
                    // Add current transcription to history
                    self.transcriptionHistory.insert(self.currentSessionText, at: 0)
                    
                    // Limit history size
                    if self.transcriptionHistory.count > self.maxHistoryItems {
                        self.transcriptionHistory.removeLast()
                    }
                }
                
                // Keep the lastTranscribedText for display until next recording starts
                // but reset the session text
                self.currentSessionText = ""
            }
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        
        // Reset only the display text for the current session
        currentSessionText = ""
        lastTranscribedText = ""
        
        // Tell the transcription service we're starting to record
        transcriptionService.startRecording()
        
        // Start audio recording immediately so no audio is missed
        audioRecorder.startRecording()
        
        // Reset text injector
        textInjector.reset()
        
        // Play sound to indicate recording started
        startSound?.play()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop audio recording immediately
        // This will trigger the onRecordingComplete callback which sends the audio data to the transcription service
        audioRecorder.stopRecording()
        isRecording = false
        
        // Note: We don't add to history here anymore - that happens in onTranscriptionComplete
        
        // Play sound to indicate recording stopped
        endSound?.play()
    }
    
    func getStatusIcon() -> String {
        return isRecording ? recordingIcon : idleIcon
    }
    
    deinit {
        keyMonitor.stop()
        
        if isRecording {
            audioRecorder.stopRecording()
        }
        
        transcriptionService.cancelTranscription()
    }
} 