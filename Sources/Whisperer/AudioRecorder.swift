import Foundation
import AVFoundation
import CoreAudio

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
    
    // Error callback when recording fails
    var onRecordingError: ((String) -> Void)?
    
    // Currently selected input device
    private var selectedInputDeviceID: AudioDeviceID?
    
    // Store available devices
    private var availableInputDevices: [(id: AudioDeviceID, name: String)] = []
    
    override init() {
        super.init()
        setupAudioEngine()
        
        // Register for device property changed notifications
        registerForDeviceNotifications()
    }
    
    deinit {
        // For deinit, we need to handle this in a way that doesn't capture self
        // Create local snapshot of variables needed
        let localIsRecording = isRecording
        let localInputNode = inputNode
        let localAudioEngine = audioEngine
        
        // Capture the observer to unregister later
        let localSelf = self
        
        // Schedule cleanup on the main actor without capturing self
        if localIsRecording {
            Task.detached { @MainActor in
                // Stop the engine without using instance methods
                localAudioEngine?.stop()
                localInputNode?.removeTap(onBus: 0)
                
                // Unregister from device notifications
                localSelf.unregisterFromDeviceNotifications()
            }
        } else {
            // If not recording, we can do simple cleanup
            localInputNode?.removeTap(onBus: 0)
            localAudioEngine?.stop()
            
            // Unregister in a detached task
            Task.detached { @MainActor in
                localSelf.unregisterFromDeviceNotifications()
            }
        }
    }
    
    // MARK: - Device Notification Handling
    
    // Property listener function that will be called when audio devices change
    private var deviceListenerProc: AudioObjectPropertyListenerProc = { _, propAddress, _, _ -> OSStatus in
        // Use Task to get back to main actor
        Task { @MainActor in
            NotificationCenter.default.post(name: .audioDevicesChanged, object: nil)
        }
        return noErr
    }
    
    private func registerForDeviceNotifications() {
        // Listen for device changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            deviceListenerProc,
            nil
        )
        
        if status != noErr {
            log("Failed to register for device property changes")
        }
        
        // Listen for notifications about audio device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioDeviceChange),
            name: .audioDevicesChanged,
            object: nil
        )
    }
    
    private func unregisterFromDeviceNotifications() {
        NotificationCenter.default.removeObserver(self, name: .audioDevicesChanged, object: nil)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            deviceListenerProc,
            nil
        )
    }
    
    @objc private func handleAudioDeviceChange(notification: Notification) {
        log("Audio devices changed")
        
        // If we're currently recording, check if our selected device is still available
        if isRecording, let selectedID = selectedInputDeviceID {
            refreshDeviceList()
            
            // Check if our device is still in the list
            if !availableInputDevices.contains(where: { $0.id == selectedID }) {
                log("Selected device no longer available, restarting")
                restartAudioEngine()
            }
        }
    }
    
    private func setupAudioEngine() {
        log("Setting up new audio engine instance...")
        audioEngine = AVAudioEngine()

        // Correctly apply the selected input device directly to the engine instance
        if let deviceID = selectedInputDeviceID {
            log("Applying selected device ID \(deviceID) to the new engine instance.")
            guard let inputUnit = audioEngine.inputNode.audioUnit else {
                log("Error: Failed to get input audio unit for engine configuration.")
                // Signal error - maybe the engine is in a bad state?
                onRecordingError?("Internal audio setup error (failed to get unit).")
                return
            }

            // Set the kAudioOutputUnitProperty_CurrentDevice property
            var deviceIDProperty = deviceID // Needs to be var for pointer
            let status = AudioUnitSetProperty(
                inputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0, // input bus
                &deviceIDProperty,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if status != noErr {
                log("Error: Failed to set input device on audio unit. OSStatus: \(status)")
                // Signal error
                onRecordingError?("Internal audio setup error (failed to set device property).")
                return
            }
            log("Successfully applied device ID \(deviceID) to the engine's input node.")
        } else {
            log("No specific input device selected, using system default for the new engine instance.")
        }

        // Get the input node AFTER setting the device
        inputNode = audioEngine.inputNode

        // Use the input node's OUTPUT format for the tap, as this reflects the format after device selection
        let inputFormat = inputNode.outputFormat(forBus: 0)
        log("Input node format after device setup: \(inputFormat)")

        // Check if the format is valid before installing the tap
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            log("Error: Invalid input format obtained after setting device: \(inputFormat). Cannot install tap.")
            onRecordingError?("Internal audio setup error (invalid format).")
            return
        }

        // Install tap on input node with the potentially updated format
        log("Installing tap on input node (bus 0, buffer size \(bufferSize))")
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self, self.isRecording else { return }
            
            // Log when a buffer is received
            // self.log("Received audio buffer at time: \(time)") // Keep this commented unless debugging buffer flow
            
            // Convert to the format we need (16kHz, 16-bit, mono) for the transcription service
            if let convertedBuffer = self.convertBufferToFormat(buffer) {
                self.audioBuffers.append(convertedBuffer)
            }
        }
        log("Tap installed successfully on input node.")
    }
    
    // Restart the audio engine to adapt to device changes
    private func restartAudioEngine() {
        guard isRecording else { return }
        
        // Remember we were recording
        let wasRecording = isRecording
        
        log("Restarting audio engine due to device change...")
        // Stop existing setup
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        // Set up again with the new device configuration applied correctly
        setupAudioEngine()
        
        // Start again if we were recording
        // Note: setupAudioEngine might have returned early if there was an error
        // We might need a state check here, but let's first see if correct setup fixes it.
        if wasRecording { // Always true due to guard, but semantically correct
            do {
                log("Attempting to start restarted audio engine...")
                try audioEngine.start()
                log("Restarted audio engine started successfully.")
            } catch {
                log("Failed to restart audio engine: \(error.localizedDescription). Error details: \(error)")
                isRecording = false // Update state
                // Ensure this error propagates
                onRecordingError?("Audio device changed and couldn't reconnect: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Device Management
    
    private func refreshDeviceList() {
        // Get all audio devices
        var deviceIDs = [AudioDeviceID]()
        var propSize: UInt32 = 0
        
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // First get the size of the deviceIDs array
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            0,
            nil,
            &propSize
        )
        
        if status != noErr {
            log("Error getting device list size: \(status)")
            return
        }
        
        // Calculate number of devices
        let deviceCount = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        
        // Create array to hold the device IDs
        deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        // Get the device IDs
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            0,
            nil,
            &propSize,
            &deviceIDs
        )
        
        if status != noErr {
            log("Error getting device list: \(status)")
            return
        }
        
        // Clear previous list
        availableInputDevices.removeAll()
        
        // Get information for each device
        for deviceID in deviceIDs {
            // Check if device has input capability
            if hasInputCapability(deviceID: deviceID) {
                if let name = getDeviceName(deviceID: deviceID) {
                    availableInputDevices.append((id: deviceID, name: name))
                }
            }
        }
    }
    
    private func hasInputCapability(deviceID: AudioDeviceID) -> Bool {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size of the stream configuration
        var propSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propAddress,
            0,
            nil,
            &propSize
        )
        
        if status != noErr {
            return false
        }
        
        // Get the stream configuration
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propSize))
        defer { bufferList.deallocate() }
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &propAddress,
            0,
            nil,
            &propSize,
            bufferList
        )
        
        if status != noErr {
            return false
        }
        
        // Check if there are any input channels
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Use UnsafeMutablePointer<Unmanaged<CFString>?> instead of var name: CFString?
        var unmanagedName: Unmanaged<CFString>?
        var propSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propAddress,
            0,
            nil,
            &propSize,
            &unmanagedName
        )
        
        // Check status and safely get the retained CFString value
        if status != noErr || unmanagedName == nil {
            return nil
        }
        
        // Take ownership of the retained CFString and convert to Swift String
        return unmanagedName!.takeRetainedValue() as String
    }
    
    private func getDefaultInputDeviceID() -> AudioDeviceID? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            0,
            nil,
            &propSize,
            &deviceID
        )
        
        if status != noErr || deviceID == 0 {
            return nil
        }
        
        return deviceID
    }
    
    private func setDefaultInputDevice(deviceID: AudioDeviceID) -> Bool {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Create a mutable copy of deviceID to pass as inout
        var mutableDeviceID = deviceID
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        
        return status == noErr
    }
    
    // MARK: - Public Device Methods
    
    // Get list of available audio input devices
    func getAvailableInputDevices() -> [(id: String, name: String)] {
        refreshDeviceList()
        
        // Convert AudioDeviceID to String for the public API
        return availableInputDevices.map { (id: String(describing: $0.id), name: $0.name) }
    }
    
    // Set the audio input device to use
    func setInputDevice(deviceID: String) {
        // Convert from string back to AudioDeviceID
        guard let numericID = UInt32(deviceID),
              let audioDeviceID = AudioDeviceID(exactly: numericID) else {
            log("Invalid device ID format")
            return
        }
        
        // Check if device exists
        refreshDeviceList()
        guard availableInputDevices.contains(where: { $0.id == audioDeviceID }) else {
            log("Could not find input device with ID: \(deviceID)")
            onRecordingError?("Could not find selected microphone")
            return
        }
        
        // Store the current recording state BEFORE changing the device
        let wasRecording = isRecording
        
        // Set as selected device
        selectedInputDeviceID = audioDeviceID
        
        // Try to set as default input device
        if !setDefaultInputDevice(deviceID: audioDeviceID) {
            log("Failed to set default input device")
            onRecordingError?("Failed to change microphone")
            // Revert selected device ID on failure? Maybe not, user might retry.
            return
        }
        
        log("Changed audio input to device: \(audioDeviceID). Reconfiguring engine...")

        // --- Teardown existing engine state --- 
        if audioEngine != nil && audioEngine.isRunning {
             log("Stopping existing audio engine before device change.")
             audioEngine.stop()
        }
        // Always remove the tap if inputNode exists
        if inputNode != nil {
             log("Removing tap from input node.")
             inputNode.removeTap(onBus: 0)
        } else {
             log("Input node was nil, skipping tap removal.")
        }
        // Nil out engine and node to ensure clean setup
        audioEngine = nil
        inputNode = nil
        // We are no longer recording after teardown
        isRecording = false 
        
        // --- Setup new engine with the new device --- 
        log("Calling setupAudioEngine to apply new device setting.")
        setupAudioEngine() // This uses the new selectedInputDeviceID
        
        // If setup failed, audioEngine might be nil or setupAudioEngine might have signalled an error.
        guard audioEngine != nil, inputNode != nil else {
             log("Engine or inputNode is nil after setup attempt following device change.")
             // isRecording is already false
             // Error message should have been set by setupAudioEngine
             return
        }
        
        // --- Restart recording if it was active before --- 
        if wasRecording {
             log("Attempting to restart recording after device change...")
             do {
                 try audioEngine.start()
                 isRecording = true // Mark as recording again *only on success*
                 log("Successfully restarted recording after device change.")
                 startSilenceWatchdog() // Restart watchdog for the new recording session
             } catch {
                 log("Failed to start audio engine after device change: \(error.localizedDescription)")
                 isRecording = false // Ensure state is correct
                 onRecordingError?("Failed to restart recording after device change: \(error.localizedDescription)")
             }
        } else {
             // If we weren't recording, the engine is now set up and ready for the *next* recording.
             log("Audio engine reconfigured for new device. Ready for next recording.")
        }
    }
    
    // Get the currently selected device ID
    func getCurrentInputDeviceID() -> String? {
        if let selectedID = selectedInputDeviceID {
            return String(describing: selectedID)
        }
        
        // Get the system default
        if let defaultID = getDefaultInputDeviceID() {
            return String(describing: defaultID)
        }
        
        return nil
    }
    
    // MARK: - Audio Processing
    
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
            
            // Set up a watchdog to detect if we're not getting any audio
            startSilenceWatchdog()
        } catch {
            log("Failed to start audio recording: \(error.localizedDescription)")
            onRecordingError?("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    // Monitor for audio data to ensure we're actually recording
    private func startSilenceWatchdog() {
        // Capture the initial buffer count
        let initialBufferCount = audioBuffers.count
        
        // Check after 2 seconds if we've received any audio
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // If we're still recording but received no audio data, report an error
            if isRecording && audioBuffers.count == initialBufferCount {
                log("No audio data received after 2 seconds - possible device issue")
                onRecordingError?("No audio detected. Microphone may be muted or unavailable.")
            }
        }
    }
    
    // Regular MainActor method since we want to call it from the main actor context
    func stopRecording() {
        // Log the state when stopRecording is called
        log("stopRecording called. isRecording: \(isRecording), buffer count: \(audioBuffers.count)")
        
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        isRecording = false
        
        log("Audio recording stopped")
        
        // Get the audio data and call the completion handler
        if let audioData = getAudioData() {
            if audioData.count < 100 {
                log("Audio data too small to process")
                onRecordingError?("Recording was too quiet or microphone may be muted")
                return
            }
            onRecordingComplete?(audioData)
        } else {
            log("No audio data captured")
            onRecordingError?("No audio was captured. Check your microphone.")
        }
        
        // Reinstall tap for next recording
        setupAudioEngine()
    }
    
    // Convert the current audio buffer to 16-bit PCM data
    private func getAudioData() -> Data? {
        guard !audioBuffers.isEmpty else { return nil }
        
        // Combine all audio buffers into one data object
        var combinedData = Data()
        
        // Add half second of silence at the beginning
        if let silencePadding = generateSilencePadding() {
            combinedData.append(silencePadding)
        }
        
        for buffer in audioBuffers {
            guard let audioBuffer = buffer.int16ChannelData?[0] else { continue }
            
            let frameLength = Int(buffer.frameLength)
            let data = Data(bytes: audioBuffer, count: frameLength * 2) // 2 bytes per sample for Int16
            combinedData.append(data)
        }
        
        // Add half second of silence at the end
        if let silencePadding = generateSilencePadding() {
            combinedData.append(silencePadding)
        }
        
        return combinedData
    }
    
    // Generate half a second of silence padding (16kHz, 16-bit, mono)
    private func generateSilencePadding() -> Data? {
        // For 16kHz audio, half a second is 8000 samples
        let sampleCount = 8000
        
        // Create a buffer of zeros (silence)
        var silenceBuffer = [Int16](repeating: 0, count: sampleCount)
        
        // Convert to Data
        return Data(bytes: &silenceBuffer, count: sampleCount * 2) // 2 bytes per sample for Int16
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

// Notification for audio device changes
extension Notification.Name {
    static let audioDevicesChanged = Notification.Name("audioDevicesChanged")
} 
