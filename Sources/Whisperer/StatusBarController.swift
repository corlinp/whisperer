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
    @Published var isToggleMode = false
    @Published var errorMessage: String? = nil
    @Published var availableMicrophones: [(id: String, name: String)] = []
    @Published var selectedMicrophoneID: String? = nil
    
    // Maximum number of transcriptions to keep in history
    private let maxHistoryItems = 3
    
    // Current session's accumulating transcription text
    private var currentSessionText = ""
    
    // For tracking recording duration
    private var recordingStartTime: Date? = nil
    private var keyPressStartTime: Date? = nil
    
    // For tracking transcription timeouts
    private var transcriptionTimeoutTask: Task<Void, Never>? = nil
    private let transcriptionTimeout: TimeInterval = 30 // seconds
    
    // For auto-stopping long recordings
    private var recordingAutoStopTask: Task<Void, Never>? = nil
    private let maxRecordingTime: TimeInterval = 300 // 5 minutes in seconds
    
    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private var transcriptionService: TranscriptionService! = nil
    private let textInjector = TextInjector()
    
    // Status icons
    private let idleIcon = "waveform"
    private let recordingIcon = "waveform.circle.fill"
    private let transcribingIcon = "waveform.circle"
    private let errorIcon = "waveform.badge.exclamationmark"
    
    // Feedback sounds
    private let startSound = NSSound(named: "Pop")
    private let endSound = NSSound(named: "Blow")
    private let shortRecordingSound = NSSound(named: "Basso") // Sound for too-short recordings
    private let errorSound = NSSound(named: "Sosumi") // Sound for errors
    
    init() {
        // First create the actor
        transcriptionService = TranscriptionService()
        
        // Then set up everything else
        setupKeyMonitor()
        setupAudioRecorder()
        setupTranscriptionService()
        
        // Get available microphones
        refreshMicrophoneList()
    }
    
    private func setupKeyMonitor() {
        keyMonitor.onRightOptionKeyDown = { [weak self] in
            guard let self = self else { return }
            // Store key press start time for measuring duration
            self.keyPressStartTime = Date()
            
            if !self.isRecording {
                // Start recording if not already recording
                self.startRecording()
            }
        }
        
        keyMonitor.onRightOptionKeyUp = { [weak self] in
            guard let self = self else { return }
            
            if let keyPressStart = self.keyPressStartTime {
                let keyPressDuration = Date().timeIntervalSince(keyPressStart)
                
                if keyPressDuration < 0.5 {
                    // Short key press
                    if self.isRecording {
                        if self.isToggleMode {
                            // We're in toggle mode and recording, so stop recording
                            self.stopRecording()
                            self.isToggleMode = false
                        } else {
                            // We just started recording with a short press, enable toggle mode
                            // so the recording continues until next key press
                            self.isToggleMode = true
                        }
                    }
                } else {
                    // Long key press: traditional hold-to-record behavior
                    if !self.isToggleMode {
                        // Only stop if we're not in toggle mode
                        self.stopRecording()
                    }
                }
            }
            
            // Reset the key press start time
            self.keyPressStartTime = nil
        }
        
        // Start monitoring keys
        keyMonitor.start()
    }
    
    private func setupAudioRecorder() {
        // Set up error callback
        audioRecorder.onRecordingError = { [weak self] errorMessage in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Stop recording if we're still recording
                if self.isRecording {
                    self.isRecording = false
                    self.isToggleMode = false
                }
                
                // Set error message
                self.errorMessage = errorMessage
                self.connectionState = "Error"
                
                // Play error sound
                self.errorSound?.play()
                
                // Clear error after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    if self.errorMessage == errorMessage {
                        self.errorMessage = nil
                        if self.connectionState == "Error" {
                            self.connectionState = "Idle"
                        }
                    }
                }
            }
        }
        
        // Keep existing completion callback
        audioRecorder.onRecordingComplete = { [weak self] audioData in
            guard let self = self else { return }
            // Send the complete audio data for transcription
            Task {
                await self.transcriptionService.finishRecording(withAudioData: audioData)
            }
        }
    }
    
    func refreshMicrophoneList() {
        // Get list of available microphones
        availableMicrophones = audioRecorder.getAvailableInputDevices()
        
        // Get currently selected microphone
        selectedMicrophoneID = audioRecorder.getCurrentInputDeviceID()
        
        // If no microphones are available, show an error
        if availableMicrophones.isEmpty {
            errorMessage = "No microphones found. Check your audio devices."
            connectionState = "Error"
            
            // Clear error after a delay
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if self.errorMessage == "No microphones found. Check your audio devices." {
                    self.errorMessage = nil
                    if self.connectionState == "Error" {
                        self.connectionState = "Idle"
                    }
                }
            }
        }
    }
    
    func selectMicrophone(deviceID: String) {
        // Set selected microphone
        audioRecorder.setInputDevice(deviceID: deviceID)
        
        // Update the UI
        selectedMicrophoneID = deviceID
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
        
        // Clear any previous error message
        errorMessage = nil
        
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
        
        // Set up auto-stop for long recordings
        startRecordingAutoStop()
    }
    
    private func startRecordingAutoStop() {
        // Cancel any existing auto-stop task
        recordingAutoStopTask?.cancel()
        
        // Create a new auto-stop task
        recordingAutoStopTask = Task { @MainActor in
            do {
                // Wait for the maximum recording duration
                try await Task.sleep(nanoseconds: UInt64(maxRecordingTime * 1_000_000_000))
                
                // If we reach here without cancellation, recording has gone on too long
                if self.isRecording {
                    print("Recording automatically stopped after \(maxRecordingTime/60) minutes")
                    
                    // Provide feedback to the user
                    NSSound(named: "Submarine")?.play()
                    
                    // Stop recording and reset toggle mode
                    self.stopRecording()
                    self.isToggleMode = false
                    
                    // Change last transcribed text to indicate auto-stop
                    if !self.currentSessionText.isEmpty {
                        self.currentSessionText += " [Auto-stopped after 5 minutes]"
                        self.lastTranscribedText = self.currentSessionText
                    }
                }
            } catch {
                // Task was canceled, which is expected behavior
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Cancel auto-stop task
        recordingAutoStopTask?.cancel()
        recordingAutoStopTask = nil
        
        // Calculate recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            
            // For short recordings (< 0.5 seconds), consider it a mistake and don't process
            // but only when not in toggle mode
            if duration < 0.5 && !isToggleMode {
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
        } else if connectionState == "Error" {
            return errorIcon
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
        recordingAutoStopTask?.cancel()
        
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