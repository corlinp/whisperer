import SwiftUI
import AVFoundation

// Define a notification name for transcription completion
extension Notification.Name {
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
}

@MainActor
class StatusBarController: ObservableObject {
    @Published var isMenuOpen = false
    @Published var isRecording = false
    @Published var lastTranscribedText = ""
    @Published var transcriptionHistory: [String] = []
    @Published var connectionState = "Idle"
    @Published var lastTranscriptionDuration: Double? = nil
    
    // Maximum number of transcriptions to keep in history
    private let maxHistoryItems = 3
    
    // Current session's accumulating transcription text
    private var currentSessionText = ""
    
    // For tracking recording duration
    private var recordingStartTime: Date? = nil
    
    // For tracking transcription timeouts
    private var transcriptionTimeoutTask: Task<Void, Never>? = nil
    private let transcriptionTimeout: TimeInterval = 30 // seconds
    
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private var transcriptionService: TranscriptionService! = nil
    private let textInjector = TextInjector()
    
    // Status icons
    private let idleIcon = "waveform"
    private let recordingIcon = "waveform.circle.fill"
    private let transcribingIcon = "waveform.circle"
    
    // Feedback sounds
    private let startSound = NSSound(named: "Pop")
    private let endSound = NSSound(named: "Blow")
    private let shortRecordingSound = NSSound(named: "Basso") // Sound for too-short recordings
    
    init() {
        // First create the actor
        transcriptionService = TranscriptionService()
        
        // Then set up everything else
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
            Task {
                await self.transcriptionService.finishRecording(withAudioData: audioData)
            }
        }
    }
    
    private func setupTranscriptionService() {
        // Register callbacks through proper API methods
        Task {
            await setupCallbacks()
        }
    }
    
    private func setupCallbacks() async {
        // Create local copies of the callbacks
        let stateChangedCallback: (TranscriptionService.ConnectionState) -> Void = { [weak self] state in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch state {
                case .idle:
                    self.connectionState = "Idle"
                    // Cancel any timeout tasks when we reach idle state
                    self.transcriptionTimeoutTask?.cancel()
                    self.transcriptionTimeoutTask = nil
                case .recording:
                    self.connectionState = "Recording"
                case .transcribing:
                    self.connectionState = "Transcribing"
                    // Start timeout task when transcription begins
                    self.startTranscriptionTimeout()
                case .error:
                    self.connectionState = "Error"
                    // Reset to idle after a brief delay if there's an error
                    self.scheduleResetToIdle()
                }
            }
        }
        
        let receivedCallback: (String) -> Void = { [weak self] text in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Append the new text to the current session's text
                self.currentSessionText += text
                self.lastTranscribedText = self.currentSessionText
                
                // Inject the transcribed text delta to the active application
                self.textInjector.injectText(text)
            }
        }
        
        let completeCallback: () -> Void = { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Only add to history if we have some text
                if !self.currentSessionText.isEmpty {
                    // Add current transcription to history
                    self.transcriptionHistory.insert(self.currentSessionText, at: 0)
                    
                    // Limit history size
                    if self.transcriptionHistory.count > self.maxHistoryItems {
                        self.transcriptionHistory.removeLast()
                    }
                    
                    // Post notification for completed transcription with duration
                    self.notifyTranscriptionCompleted()
                }
                
                // Keep the lastTranscribedText for display until next recording starts
                // but reset the session text
                self.currentSessionText = ""
            }
        }
        
        // Set the callbacks on the actor
        await transcriptionService.setCallbacks(
            onStateChanged: stateChangedCallback,
            onReceived: receivedCallback,
            onComplete: completeCallback
        )
    }
    
    // New method to notify when a transcription is completed
    private func notifyTranscriptionCompleted() {
        // Only notify if we have duration data
        if let duration = lastTranscriptionDuration {
            // Post notification with user info containing duration
            NotificationCenter.default.post(
                name: .transcriptionCompleted,
                object: self,
                userInfo: ["duration": duration]
            )
        }
    }
    
    private func startTranscriptionTimeout() {
        // Cancel any existing timeout task
        transcriptionTimeoutTask?.cancel()
        
        // Create a new timeout task
        transcriptionTimeoutTask = Task { @MainActor in
            do {
                // Wait for the timeout duration
                try await Task.sleep(nanoseconds: UInt64(transcriptionTimeout * 1_000_000_000))
                
                // If we reach here without cancellation, the transcription has timed out
                // Check if we're still in transcribing state
                if self.connectionState == "Transcribing" {
                    print("Transcription timed out after \(transcriptionTimeout) seconds")
                    
                    // Cancel the transcription
                    await self.transcriptionService.cancelTranscription()
                    
                    // Reset state
                    self.connectionState = "Idle"
                    
                    // Clear the timeout task
                    self.transcriptionTimeoutTask = nil
                }
            } catch {
                // Task was canceled, which is expected behavior
            }
        }
    }
    
    private func scheduleResetToIdle() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if self.connectionState == "Error" {
                self.connectionState = "Idle"
            }
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        
        // Reset only the display text for the current session
        currentSessionText = ""
        lastTranscribedText = ""
        lastTranscriptionDuration = nil
        
        // Record start time for duration tracking
        recordingStartTime = Date()
        
        // Tell the transcription service we're starting to record
        Task {
            await transcriptionService.startRecording()
        }
        
        // Start audio recording immediately so no audio is missed
        audioRecorder.startRecording()
        
        // Reset text injector
        textInjector.reset()
        
        // Play sound to indicate recording started
        startSound?.play()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Calculate recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            
            // For short recordings (< 0.5 seconds), consider it a mistake and don't process
            if duration < 0.5 {
                // Need to clean up resources without triggering the onRecordingComplete callback
                isRecording = false
                
                // Reset recording state and UI
                currentSessionText = ""
                lastTranscribedText = ""
                lastTranscriptionDuration = nil
                
                // Manually stop the audio engine without triggering the callback
                audioRecorder.cancelRecording()
                
                // Ensure the connection state is reset
                Task {
                    await transcriptionService.cancelTranscription()
                }
                
                // Play a different sound to indicate we won't transcribe it
                shortRecordingSound?.play()
                return
            }
            
            // Set the duration for valid recordings
            lastTranscriptionDuration = duration
        }
        
        // Stop audio recording immediately
        // This will trigger the onRecordingComplete callback which sends the audio data to the transcription service
        audioRecorder.stopRecording()
        isRecording = false
        
        // Note: We don't add to history here anymore - that happens in onTranscriptionComplete
        
        // Play sound to indicate recording stopped
        endSound?.play()
    }
    
    func getStatusIcon() -> String {
        if isRecording {
            return recordingIcon
        } else if connectionState == "Transcribing" {
            return transcribingIcon
        } else {
            return idleIcon
        }
    }
    
    // Returns true if the app is in an active state (recording or transcribing)
    func isActiveState() -> Bool {
        return isRecording || connectionState == "Transcribing"
    }
    
    deinit {
        // Capture non-isolated properties that don't need MainActor access
        let ts = transcriptionService
        let ar = audioRecorder
        let km = keyMonitor
        
        // Cancel any timeout tasks
        transcriptionTimeoutTask?.cancel()
        
        // Create a fully detached task without any reference to self
        Task.detached {
            // Perform synchronous operations that need MainActor
            await MainActor.run {
                // Clean up key monitor (synchronous operation)
                km.stop()
            }
            
            // Perform async operation separately
            if let transcriptionService = ts {
                await transcriptionService.cancelTranscription()
            }
            
            // Stop recording (requires await since it's actor-isolated)
            await ar.stopRecording()
        }
    }
} 