import Foundation
import AVFoundation

// Extension to allow easy conversion of integers to Data
extension FixedWidthInteger {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

// Make this an actor to eliminate data races
actor TranscriptionService {
    // Log levels
    enum LogLevel: Int {
        case none = 0
        case error = 1
        case info = 2
        case debug = 3
    }
    
    // Connection states
    enum ConnectionState {
        case idle
        case recording
        case transcribing
        case error(String)
    }
    
    // Set the desired log level
    private let logLevel: LogLevel = .info
    
    // State management
    private var connectionState = ConnectionState.idle {
        didSet {
            Task { @MainActor in
                await self.onConnectionStateChanged?(self.connectionState)
            }
            
            switch connectionState {
            case .idle:
                log(.info, message: "State: Idle")
            case .recording:
                log(.info, message: "State: Recording")
            case .transcribing:
                log(.info, message: "State: Transcribing")
            case .error(let message):
                log(.error, message: "State: Error - \(message)")
            }
        }
    }
    
    private var recordedAudioData: Data?
    private var transcriptionTask: URLSessionDataTask?
    
    // Callbacks
    private var onTranscriptionReceived: ((String) -> Void)?
    private var onConnectionStateChanged: ((ConnectionState) -> Void)?
    private var onTranscriptionComplete: (() -> Void)?
    
    // Retry configuration
    private let maxRetries = 5
    private var currentRetryCount = 0
    
    private var apiKey: String {
        // First check user defaults
        if let key = UserDefaults.standard.string(forKey: "openAIApiKey"), !key.isEmpty {
            return key
        }
        
        // Fall back to environment variable
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
    
    private var customPrompt: String {
        return UserDefaults.standard.string(forKey: "customPrompt") ?? ""
    }
    
    init() {}
    
    // Start recording
    func startRecording() {
        log(.info, message: "Starting recording")
        connectionState = .recording
        recordedAudioData = nil
    }
    
    // Called when recording is finished
    func finishRecording(withAudioData audioData: Data) {
        log(.info, message: "Recording finished, sending audio for transcription")
        
        // Ensure audio data exists and has reasonable size
        guard !audioData.isEmpty, audioData.count > 100 else {
            log(.error, message: "Audio data too small or empty")
            connectionState = .error("Audio data too small or empty")
            
            // Ensure we still complete the transcription when we have no data
            Task { @MainActor in
                await self.onTranscriptionComplete?()
            }
            
            // Return to idle state after reporting error
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                self.connectionState = .idle
            }
            
            return
        }
        
        recordedAudioData = audioData
        sendAudioForTranscription()
    }
    
    private func sendAudioForTranscription() {
        guard let audioData = recordedAudioData else {
            connectionState = .error("No audio data to transcribe")
            return
        }
        
        guard !apiKey.isEmpty else {
            connectionState = .error("OpenAI API key is not set")
            return
        }
        
        connectionState = .transcribing
        
        // Create the URL for the transcription API
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            connectionState = .error("Invalid URL for OpenAI API")
            return
        }
        
        // Create a boundary for multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create the request body
        request.httpBody = createRequestBody(boundary: boundary, audioData: audioData)
        
        // Cancel any existing task
        transcriptionTask?.cancel()
        
        log(.info, message: "Sending audio for transcription...")
        
        // Capture weak self before creating URLSession task
        let weakSelf = self
        
        // Create a data task for the request with streaming support
        let session = URLSession.shared
        transcriptionTask = session.dataTask(with: request) { data, response, error in
            Task {
                // Re-obtain self inside the task to ensure actor isolation
                await weakSelf.handleTranscriptionResponse(data: data, response: response, error: error)
            }
        }
        
        transcriptionTask?.resume()
    }
    
    // Handle the transcription response in actor-isolated context
    private func handleTranscriptionResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            log(.error, message: "Transcription request failed: \(error.localizedDescription)")
            
            // Check if this is a cancellation - don't retry in that case
            if (error as NSError).domain == NSURLErrorDomain && 
               (error as NSError).code == NSURLErrorCancelled {
                connectionState = .error("Request cancelled")
                return
            }
            
            retryTranscriptionIfPossible(with: "Request failed: \(error.localizedDescription)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            connectionState = .error("Invalid response from server")
            return
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = parseErrorMessage(data: data)
            log(.error, message: "Server returned error: \(httpResponse.statusCode), \(errorMessage)")
            
            // Check if this is a server error (5xx) that should be retried
            if httpResponse.statusCode >= 500 && httpResponse.statusCode < 600 {
                retryTranscriptionIfPossible(with: "Server error: \(httpResponse.statusCode)")
                return
            }
            
            // For other errors, don't retry
            connectionState = .error("Server error: \(httpResponse.statusCode)")
            return
        }
        
        // Reset retry count on success
        currentRetryCount = 0
        
        guard let data = data else {
            connectionState = .error("No data received")
            return
        }
        
        log(.info, message: "Transcription data received, processing SSE response")
        
        // Process the SSE data
        handleSSEData(data)
        
        // Mark as complete
        log(.info, message: "Transcription complete")
        connectionState = .idle
    }
    
    // New function to handle retries with exponential backoff
    private func retryTranscriptionIfPossible(with errorMessage: String) {
        if currentRetryCount < maxRetries {
            currentRetryCount += 1
            
            // Calculate exponential backoff delay: 2^retry * 250ms 
            // This gives: 250ms, 500ms, 1s, 2s, 4s for retries 1-5
            let delayInSeconds = pow(2.0, Double(currentRetryCount)) * 0.25
            
            log(.info, message: "Retry \(currentRetryCount)/\(maxRetries) for transcription after \(delayInSeconds)s")
            
            // Update connection state to show retry information
            connectionState = .error("\(errorMessage). Retrying (\(currentRetryCount)/\(maxRetries))...")
            
            // Schedule retry after the calculated delay
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delayInSeconds * 1_000_000_000))
                sendAudioForTranscription()
            }
        } else {
            // Max retries reached, give up
            log(.error, message: "Maximum retries (\(maxRetries)) reached for transcription")
            connectionState = .error("\(errorMessage). Max retries reached.")
            
            // Ensure we complete the transcription process even on error
            Task { @MainActor in
                await self.onTranscriptionComplete?()
            }
            
            // Reset retry count and return to idle
            currentRetryCount = 0
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                self.connectionState = .idle
            }
        }
    }
    
    private func createRequestBody(boundary: String, audioData: Data) -> Data {
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)
        
        // Add prompt parameter if available
        if !customPrompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(customPrompt)\r\n".data(using: .utf8)!)
        }
        
        // Add language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // Add stream parameter for SSE
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"stream\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        
        // Create WAV file with PCM audio data
        let wavData = createWavFileFromPCMData(audioData)
        
        // Add audio file - converted to WAV
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close the body
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    // Function to create a WAV file from the PCM audio data
    private func createWavFileFromPCMData(_ pcmData: Data) -> Data {
        // Standard WAV header for 16-bit PCM, mono, 16kHz
        var header = Data()
        
        // "RIFF" chunk descriptor
        header.append("RIFF".data(using: .ascii)!)
        
        // ChunkSize: 4 + (8 + 16) + (8 + PCM data size)
        let fileSize = 36 + pcmData.count
        header.append(UInt32(fileSize).littleEndian.data)
        
        // Format: "WAVE"
        header.append("WAVE".data(using: .ascii)!)
        
        // "fmt " sub-chunk
        header.append("fmt ".data(using: .ascii)!)
        header.append(UInt32(16).littleEndian.data) // Sub-chunk size (16 for PCM)
        header.append(UInt16(1).littleEndian.data)  // AudioFormat (1 for PCM)
        header.append(UInt16(1).littleEndian.data)  // NumChannels (1 for mono)
        header.append(UInt32(16000).littleEndian.data) // SampleRate (16kHz)
        
        // ByteRate = SampleRate * NumChannels * (BitsPerSample / 8)
        header.append(UInt32(16000 * 1 * 2).littleEndian.data)
        
        // BlockAlign = NumChannels * (BitsPerSample / 8)
        header.append(UInt16(1 * 2).littleEndian.data)
        
        // BitsPerSample (16 bits)
        header.append(UInt16(16).littleEndian.data)
        
        // "data" sub-chunk
        header.append("data".data(using: .ascii)!)
        header.append(UInt32(pcmData.count).littleEndian.data) // Sub-chunk size (raw PCM data size)
        
        // Combine header with PCM data
        var wavData = Data()
        wavData.append(header)
        wavData.append(pcmData)
        
        return wavData
    }
    
    // Process SSE data
    private func handleSSEData(_ data: Data) {
        guard let sseText = String(data: data, encoding: .utf8) else {
            log(.error, message: "Failed to decode SSE data")
            // Ensure we still complete the transcription even on error
            Task { @MainActor in
                await self.onTranscriptionComplete?()
            }
            return
        }
        
        // Split the string by double newlines, which separate SSE messages
        let eventStrings = sseText.components(separatedBy: "\n\n")
        
        // Track if we got any valid deltas
        var receivedAnyDeltas = false
        
        for eventString in eventStrings {
            if eventString.isEmpty { continue }
            
            // Extract the JSON from lines that start with "data: "
            for line in eventString.components(separatedBy: "\n") {
                if line.hasPrefix("data: ") {
                    let jsonText = String(line.dropFirst(6))
                    receivedAnyDeltas = processSSEEvent(jsonText) || receivedAnyDeltas
                }
            }
        }
        
        // Even if we didn't get valid deltas, we should complete the transcription
        Task { @MainActor in
            await self.onTranscriptionComplete?()
        }
    }
    
    // Process a single SSE event - returns true if a valid delta was processed
    private func processSSEEvent(_ jsonText: String) -> Bool {
        // Skip empty messages and special non-JSON messages
        if jsonText.isEmpty || jsonText == "[DONE]" {
            log(.debug, message: "Received end-of-stream marker")
            return false
        }
        
        guard let jsonData = jsonText.data(using: .utf8) else { 
            log(.debug, message: "Could not convert SSE text to data")
            return false
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let type = json["type"] as? String {
                
                switch type {
                case "transcript.text.delta":
                    if let delta = json["delta"] as? String {
                        log(.debug, message: "Transcription delta: \"\(delta)\"")
                        Task { @MainActor in
                            await self.onTranscriptionReceived?(delta)
                        }
                        return true
                    }
                    
                case "transcript.text.done":
                    if let fullText = json["text"] as? String {
                        log(.info, message: "Transcription complete: \"\(fullText)\"")
                    }
                    return true
                    
                default:
                    log(.debug, message: "Unhandled SSE event type: \(type)")
                }
            }
        } catch {
            // Don't treat as an error - this could be a non-JSON message or stream terminator
            log(.debug, message: "Skipping non-JSON SSE message: \(error.localizedDescription)")
        }
        
        return false
    }
    
    // Parse error message from response data
    private func parseErrorMessage(data: Data?) -> String {
        guard let errorData = data,
              let errorStr = String(data: errorData, encoding: .utf8) else {
            return "Unknown error"
        }
        
        // Try to extract a cleaner error message from JSON if possible
        do {
            if let errorJson = try JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
        } catch {
            // Just use the raw error string if we can't parse JSON
        }
        
        return errorStr
    }
    
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        // Ensure we switch back to idle state
        connectionState = .idle
        
        // Clear any stored audio data
        recordedAudioData = nil
        
        // Reset retry count
        currentRetryCount = 0
    }
    
    // Logging utility
    func log(_ level: LogLevel, message: String) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: now)
        
        if level.rawValue <= logLevel.rawValue {
            let prefix: String
            switch level {
            case .none: prefix = ""
            case .error: prefix = "❌ ERROR: "
            case .info: prefix = "ℹ️ INFO: "
            case .debug: prefix = "🔍 DEBUG: "
            }
            print("\(timestamp) \(prefix)\(message)")
        } else {
            print("\(timestamp) \(message)")
        }
    }
    
    /// Set all callbacks safely within the actor's isolation domain
    func setCallbacks(
        onStateChanged: @escaping (ConnectionState) -> Void,
        onReceived: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.onConnectionStateChanged = onStateChanged
        self.onTranscriptionReceived = onReceived
        self.onTranscriptionComplete = onComplete
    }
} 

