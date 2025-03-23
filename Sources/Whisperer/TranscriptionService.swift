import Foundation
import AVFoundation

class TranscriptionService {
    // Log levels
    enum LogLevel: Int {
        case none = 0
        case error = 1
        case info = 2
        case debug = 3
    }
    
    // Connection states
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case awaitingTranscription
        case disconnecting
    }
    
    // Set the desired log level
    private let logLevel: LogLevel = .info
    
    // WebSocket connection for streaming audio and receiving transcriptions
    private var webSocketTask: URLSessionWebSocketTask?
    private var connectionState = ConnectionState.disconnected
    private var sessionId: String?
    private var clientSecret: String?
    
    // Store buffered audio when connection isn't ready
    private var bufferedAudio: [Data] = []
    
    // Retry handling
    private let maxRetryAttempts = 3
    private var currentRetryAttempt = 0
    private var disconnectionTimer: Timer?
    
    // Transcription tracking
    private var lastCommitTime: Date?
    private var pendingDisconnect = false
    private var receivedTranscriptionAfterCommit = false
    private let maxWaitTime: TimeInterval = 5.0 // Maximum wait time for transcription
    
    // Callback for when transcribed text is received
    var onTranscriptionReceived: ((String) -> Void)?
    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    
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
    
    // Function to check if we're in a state where we can send data
    private var canSendData: Bool {
        return (connectionState == .connected || connectionState == .awaitingTranscription) && webSocketTask != nil
    }
    
    func connect() {
        guard connectionState == .disconnected else {
            log(.info, message: "Already connecting or connected")
            return
        }
        
        // Cancel any existing disconnection timer
        disconnectionTimer?.invalidate()
        disconnectionTimer = nil
        
        // Reset transcription tracking
        pendingDisconnect = false
        receivedTranscriptionAfterCommit = false
        lastCommitTime = nil
        
        guard apiKey.isEmpty == false else {
            log(.error, message: "Error: OpenAI API key is not set")
            return
        }
        
        if !apiKey.hasPrefix("sk-") {
            log(.info, message: "Warning: API key does not start with 'sk-'. This may not be a valid OpenAI API key.")
        }
        
        updateConnectionState(.connecting)
        log(.info, message: "Connecting to OpenAI Realtime API")
        
        // Create a transcription session first
        createTranscriptionSession()
    }
    
    private func updateConnectionState(_ newState: ConnectionState) {
        connectionState = newState
        onConnectionStateChanged?(newState)
        
        switch newState {
        case .disconnected:
            log(.info, message: "Connection state: Disconnected")
        case .connecting:
            log(.info, message: "Connection state: Connecting")
        case .connected:
            log(.info, message: "Connection state: Connected")
        case .awaitingTranscription:
            log(.info, message: "Connection state: Awaiting transcription completion")
        case .disconnecting:
            log(.info, message: "Connection state: Disconnecting")
        }
    }
    
    private func createTranscriptionSession() {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/transcription_sessions") else {
            log(.error, message: "Error: Invalid URL for OpenAI API")
            updateConnectionState(.disconnected)
            return
        }
        
        // Create session configuration
        let sessionConfig: [String: Any] = [
            "input_audio_format": "pcm16",
            "input_audio_transcription": [
                "model": "gpt-4o-transcribe",
                "prompt": customPrompt,
                "language": "en",
            ],
            "input_audio_noise_reduction": [
                "type": "near_field"
            ],
            "include": [
                "item.input_audio_transcription.logprobs"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        // Convert sessionConfig to JSON data
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: sessionConfig)
        } catch {
            log(.error, message: "Error serializing session config: \(error.localizedDescription)")
            updateConnectionState(.disconnected)
            return
        }
        
        // Create session
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log(.error, message: "Error creating transcription session: \(error.localizedDescription)")
                self.updateConnectionState(.disconnected)
                if self.currentRetryAttempt < self.maxRetryAttempts {
                    self.currentRetryAttempt += 1
                    self.log(.info, message: "Retrying connection (attempt \(self.currentRetryAttempt)/\(self.maxRetryAttempts))...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.connect()
                    }
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.log(.error, message: "Error: No HTTP response")
                self.updateConnectionState(.disconnected)
                return
            }
            
            if httpResponse.statusCode != 200 {
                self.log(.error, message: "Error: HTTP status code \(httpResponse.statusCode)")
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    self.log(.error, message: "Error response: \(errorString)")
                }
                self.updateConnectionState(.disconnected)
                return
            }
            
            guard let data = data else {
                self.log(.error, message: "Error: No data received")
                self.updateConnectionState(.disconnected)
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.log(.error, message: "Error parsing session response: Not a dictionary")
                    self.updateConnectionState(.disconnected)
                    return
                }
                
                if let id = json["id"] as? String {
                    self.log(.info, message: "Transcription session created with ID: \(id)")
                    self.sessionId = id
                    
                    // Extract client secret for WebSocket authentication
                    if let clientSecret = json["client_secret"] as? [String: Any],
                       let clientSecretValue = clientSecret["value"] as? String {
                        self.log(.debug, message: "Client secret obtained")
                        self.clientSecret = clientSecretValue
                        self.connectWebSocket()
                    } else {
                        self.log(.error, message: "Error: No client_secret in response")
                        self.updateConnectionState(.disconnected)
                    }
                } else {
                    self.log(.error, message: "Error: No session ID in response")
                    if let errorObj = json["error"] as? [String: Any], let message = errorObj["message"] as? String {
                        self.log(.error, message: "API error: \(message)")
                    }
                    self.updateConnectionState(.disconnected)
                }
            } catch {
                self.log(.error, message: "Error parsing session response: \(error.localizedDescription)")
                self.updateConnectionState(.disconnected)
            }
        }
        
        task.resume()
    }
    
    private func connectWebSocket() {
        guard let _ = sessionId, let clientSecret = clientSecret else {
            log(.error, message: "Error: Session ID or client secret not available")
            updateConnectionState(.disconnected)
            return
        }
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            log(.error, message: "Error: Invalid URL for OpenAI WebSocket")
            updateConnectionState(.disconnected)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.timeoutInterval = 30
        
        log(.info, message: "Creating WebSocket connection")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        // Set up a ping task to keep connection alive
        setupPingTask()
        
        // Start receiving messages
        receiveMessages()
        
        log(.info, message: "Starting WebSocket connection")
        webSocketTask?.resume()
        
        // Set connection to connected after initiating the connection
        updateConnectionState(.connected)
        currentRetryAttempt = 0
        
        // Send initial update message to configure the session
        sendTranscriptionSessionUpdate()
        
        // Send any buffered audio data
        sendBufferedAudio()
    }
    
    private func sendBufferedAudio() {
        guard !bufferedAudio.isEmpty, canSendData else {
            if !bufferedAudio.isEmpty {
                log(.info, message: "Cannot send buffered audio yet. Connection not ready.")
            }
            return
        }
        
        log(.info, message: "Sending \(bufferedAudio.count) buffered audio chunks")
        
        for audioData in bufferedAudio {
            let base64Audio = audioData.base64EncodedString()
            
            let message = """
            {
              "type": "input_audio_buffer.append",
              "audio": "\(base64Audio)"
            }
            """
            
            send(text: message)
        }
        
        // Set last commit time when sending buffered audio
        lastCommitTime = Date()
        
        // Clear the buffer after sending
        bufferedAudio.removeAll()
    }
    
    private func sendTranscriptionSessionUpdate() {
        let updateMessage = """
        {
          "type": "transcription_session.update",
          "session": {
            "input_audio_format": "pcm16",
            "input_audio_transcription": {
              "model": "gpt-4o-transcribe",
              "prompt": "\(customPrompt.replacingOccurrences(of: "\"", with: "\\\"") )",
              "language": "en"
            },
            "turn_detection": {
              "type": "server_vad",
              "threshold": 0.5,
              "prefix_padding_ms": 300,
              "silence_duration_ms": 500
            },
            "input_audio_noise_reduction": {
              "type": "near_field"
            },
            "include": [
              "item.input_audio_transcription.logprobs"
            ]
          }
        }
        """
        
        send(text: updateMessage)
    }
    
    func prepareForDisconnect() {
        // Mark that we're expecting to disconnect but waiting for transcription
        pendingDisconnect = true
        lastCommitTime = Date()
        receivedTranscriptionAfterCommit = false
        
        // Change state to awaiting transcription
        updateConnectionState(.awaitingTranscription)
        
        // Start a timeout timer in case we never get a transcription
        disconnectionTimer?.invalidate()
        disconnectionTimer = Timer.scheduledTimer(withTimeInterval: maxWaitTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // If we've waited too long with no transcription, disconnect anyway
            if self.pendingDisconnect && !self.receivedTranscriptionAfterCommit {
                self.log(.info, message: "Transcription timeout reached, disconnecting")
                self.disconnect()
            }
        }
    }
    
    func disconnect() {
        // Cancel any pending timers
        disconnectionTimer?.invalidate()
        disconnectionTimer = nil
        
        // Reset flags
        pendingDisconnect = false
        receivedTranscriptionAfterCommit = false
        
        guard connectionState != .disconnected else {
            return
        }
        
        log(.info, message: "Disconnecting WebSocket")
        updateConnectionState(.disconnecting)
        
        // Cancel any pending receive operations
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionId = nil
        clientSecret = nil
        
        updateConnectionState(.disconnected)
    }
    
    private func setupPingTask() {
        log(.debug, message: "Setting up ping task to maintain connection")
        // Store a weak reference to self
        let weakSelf = self
        
        // Use _ to discard the task but keep it running
        _ = Task {
            while connectionState != .disconnected && webSocketTask != nil {
                log(.debug, message: "Sending WebSocket ping")
                webSocketTask?.sendPing { error in
                    if let error = error {
                        Task { 
                            // This avoids the @Sendable warning since we're using a dedicated Task
                            weakSelf.log(.error, message: "Ping error: \(error.localizedDescription)")
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }
    
    private func receiveMessages() {
        guard connectionState != .disconnected, let webSocketTask = webSocketTask else {
            return
        }
        
        webSocketTask.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleReceivedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleReceivedMessage(text)
                    } else {
                        self.log(.debug, message: "Received binary data")
                    }
                @unknown default:
                    self.log(.info, message: "Received unknown message type")
                    break
                }
                
                // Continue receiving messages if still connected
                if self.connectionState != .disconnected && self.connectionState != .disconnecting {
                    self.receiveMessages()
                }
                
            case .failure(let error):
                self.log(.error, message: "WebSocket receive error: \(error.localizedDescription)")
                
                if self.connectionState != .disconnecting && self.connectionState != .disconnected {
                    self.updateConnectionState(.disconnected)
                    
                    // Attempt to reconnect if it wasn't an intentional disconnect
                    if self.currentRetryAttempt < self.maxRetryAttempts {
                        self.currentRetryAttempt += 1
                        self.log(.info, message: "WebSocket disconnected unexpectedly. Retrying connection (attempt \(self.currentRetryAttempt)/\(self.maxRetryAttempts))...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.connect()
                        }
                    }
                }
            }
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else {
            log(.error, message: "Failed to convert message to data")
            return
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log(.error, message: "Failed to parse JSON: Not a dictionary")
                return
            }
            
            if let type = json["type"] as? String {
                log(.debug, message: "Received message of type: \(type)")
                
                switch type {
                case "transcription_session.created", "transcription_session.updated":
                    if let session = json["session"] as? [String: Any], 
                       let id = session["id"] as? String {
                        log(.info, message: "Transcription session updated with ID: \(id)")
                        sessionId = id
                    }
                
                case "input_audio_buffer.speech_started":
                    log(.info, message: "Speech detected - beginning transcription")
                
                case "conversation.item.input_audio_transcription.completed":
                    // Handle complete transcription in the format from the API docs
                    if let transcript = json["transcript"] as? String {
                        log(.info, message: "Transcription completed: \"\(transcript)\"")
                        
                        // Mark that we received a transcription after the last audio commit
                        if pendingDisconnect && lastCommitTime != nil {
                            receivedTranscriptionAfterCommit = true
                            log(.info, message: "Received transcription after commit, ready to disconnect")
                            
                            // Dispatch to main thread to avoid race conditions
                            DispatchQueue.main.async {
                                // If this was a complete transcription for pending disconnect, now we can disconnect
                                if self.pendingDisconnect && self.receivedTranscriptionAfterCommit {
                                    self.log(.info, message: "Initiating disconnect after receiving transcription")
                                    // Small delay to ensure any UI updates complete
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        self.disconnect()
                                    }
                                }
                            }
                        }
                        
                        DispatchQueue.main.async {
                            // For complete transcriptions, replace the text rather than append
                            self.onTranscriptionReceived?(transcript)
                        }
                    }
                    
                case "conversation.item.input_audio_transcription.delta":
                    // Handle incremental text updates in the format from the API docs
                    if let delta = json["delta"] as? String {
                        log(.debug, message: "Transcription delta: \"\(delta)\"")
                        
                        // Mark that we received a transcription after the last audio commit
                        if pendingDisconnect && lastCommitTime != nil {
                            receivedTranscriptionAfterCommit = true
                        }
                        
                        DispatchQueue.main.async {
                            // For deltas, we pass them along as-is
                            self.onTranscriptionReceived?(delta)
                        }
                    }
                    
                case "error":
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        log(.error, message: "API error: \(message)")
                        if let code = error["code"] as? String {
                            log(.error, message: "Error code: \(code)")
                        }
                    } else {
                        log(.error, message: "Unknown error format in message")
                    }
                    
                case "input_audio_buffer.speech_stopped":
                    log(.info, message: "Speech ended")
                    
                case "input_audio_buffer.committed":
                    if let itemId = json["item_id"] as? String {
                        log(.info, message: "Audio buffer committed for item: \(itemId)")
                        
                        // Record the time of the last commit
                        lastCommitTime = Date()
                        
                        // If we're waiting to disconnect, reset the received flag
                        if pendingDisconnect {
                            receivedTranscriptionAfterCommit = false
                        }
                    }
                
                default:
                    log(.debug, message: "Unhandled message type: \(type)")
                }
            }
        } catch {
            log(.error, message: "JSON parsing error: \(error.localizedDescription)")
        }
    }
    
    func send(text: String) {
        guard canSendData else {
            log(.error, message: "Cannot send message: WebSocket not connected (state: \(connectionState))")
            return
        }
        
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                self?.log(.error, message: "Error sending WebSocket message: \(error.localizedDescription)")
            }
        }
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioData = pcmBufferToData(buffer) else {
            log(.error, message: "Failed to convert audio buffer to data")
            return
        }
        
        // If not connected yet, buffer the audio data
        if !canSendData {
            if connectionState == .connecting {
                log(.info, message: "Still connecting, buffering audio")
                bufferedAudio.append(audioData)
                return
            } else {
                log(.debug, message: "Cannot send audio: Not connected or connecting (state: \(connectionState))")
                return
            }
        }
        
        // Convert audio data to base64
        let base64Audio = audioData.base64EncodedString()
        
        // Create the audio buffer append message following the correct protocol
        let message = """
        {
          "type": "input_audio_buffer.append",
          "audio": "\(base64Audio)"
        }
        """
        
        send(text: message)
    }
    
    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            log(.error, message: "No int16ChannelData in buffer")
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        
        // For simplicity, we'll just use the first channel if it's stereo
        let audioBuffer = channelData[0]
        
        return Data(bytes: audioBuffer, count: frameLength * 2) // 2 bytes per sample for Int16
    }
    
    // Logging utility
    func log(_ level: LogLevel, message: String) {
        if level.rawValue <= logLevel.rawValue {
            let prefix: String
            switch level {
            case .none: prefix = ""
            case .error: prefix = "❌ ERROR: "
            case .info: prefix = "ℹ️ INFO: "
            case .debug: prefix = "🔍 DEBUG: "
            }
            print("\(prefix)\(message)")
        }
    }
} 

