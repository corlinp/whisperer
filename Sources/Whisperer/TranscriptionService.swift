import Foundation
import AVFoundation

@available(*, deprecated, message: "Consider using 'Task' to safely run asynchronous code")
fileprivate func asyncTask(_ block: @escaping () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        block()
    }
}

class TranscriptionService {
    // Log levels
    enum LogLevel: Int {
        case none = 0
        case error = 1
        case info = 2
        case debug = 3
    }
    
    // Set the desired log level
    private let logLevel: LogLevel = .error
    
    // WebSocket connection for streaming audio and receiving transcriptions
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var sessionId: String?
    private var clientSecret: String?
    
    // Callback for when transcribed text is received
    var onTranscriptionReceived: ((String) -> Void)?
    
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
    
    func connect() {
        guard apiKey.isEmpty == false else {
            log(.error, message: "Error: OpenAI API key is not set")
            return
        }
        
        if !apiKey.hasPrefix("sk-") {
            log(.info, message: "Warning: API key does not start with 'sk-'. This may not be a valid OpenAI API key.")
        }
        
        log(.info, message: "Connecting to OpenAI Realtime API")
        
        // Create a transcription session first
        createTranscriptionSession()
    }
    
    private func createTranscriptionSession() {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/transcription_sessions") else {
            log(.error, message: "Error: Invalid URL for OpenAI API")
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
            return
        }
        
        // Create session
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log(.error, message: "Error creating transcription session: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.log(.error, message: "Error: No HTTP response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                self.log(.error, message: "Error: HTTP status code \(httpResponse.statusCode)")
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    self.log(.error, message: "Error response: \(errorString)")
                }
                return
            }
            
            guard let data = data else {
                self.log(.error, message: "Error: No data received")
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.log(.error, message: "Error parsing session response: Not a dictionary")
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
                    }
                } else {
                    self.log(.error, message: "Error: No session ID in response")
                    if let errorObj = json["error"] as? [String: Any], let message = errorObj["message"] as? String {
                        self.log(.error, message: "API error: \(message)")
                    }
                }
            } catch {
                self.log(.error, message: "Error parsing session response: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    private func connectWebSocket() {
        guard let _ = sessionId, let clientSecret = clientSecret else {
            log(.error, message: "Error: Session ID or client secret not available")
            return
        }
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            log(.error, message: "Error: Invalid URL for OpenAI WebSocket")
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
        
        // Set connection to true after initiating the connection
        isConnected = true
        
        // Send initial update message to configure the session
        sendTranscriptionSessionUpdate()
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
    
    func disconnect() {
        log(.info, message: "Disconnecting WebSocket")
        isConnected = false  // Set this first to prevent further processing
        
        // Cancel any pending receive operations
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionId = nil
        clientSecret = nil
    }
    
    private func setupPingTask() {
        log(.debug, message: "Setting up ping task to maintain connection")
        // Store a weak reference to self and the error handler function
        let weakSelf = self
        let errorHandler: (Error) -> Void = { error in
            let message = "Ping error: \(error.localizedDescription)"
            asyncTask {
                // This avoids the @Sendable warning since we're not capturing self directly
                weakSelf.log(.error, message: message)
            }
        }
        
        // Use _ to discard the task but keep it running
        _ = Task {
            while isConnected && webSocketTask != nil {
                log(.debug, message: "Sending WebSocket ping")
                webSocketTask?.sendPing { error in
                    if let error = error {
                        errorHandler(error)
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
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
                
                // Continue receiving messages
                self.receiveMessages()
                
            case .failure(let error):
                self.log(.error, message: "WebSocket receive error: \(error.localizedDescription)")
                self.isConnected = false
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
                switch type {
                case "transcription_session.created":
                    if let session = json["session"] as? [String: Any], 
                       let id = session["id"] as? String {
                        log(.info, message: "Transcription session created with ID: \(id)")
                        sessionId = id
                    }
                
                case "input_audio_buffer.speech_started":
                    log(.info, message: "Speech detected - beginning transcription")
                
                case "conversation.item.input_audio_transcription.completed":
                    // Handle complete transcription in the format from the API docs
                    if let transcript = json["transcript"] as? String {
                        log(.info, message: "Transcription completed: \"\(transcript)\"")
                        DispatchQueue.main.async {
                            self.onTranscriptionReceived?(transcript)
                        }
                    }
                    
                case "conversation.item.input_audio_transcription.delta":
                    // Handle incremental text updates in the format from the API docs
                    if let delta = json["delta"] as? String {
                        log(.debug, message: "Transcription delta: \"\(delta)\"")
                        DispatchQueue.main.async {
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
                
                default:
                    log(.debug, message: "Unhandled message type: \(type)")
                }
            }
        } catch {
            log(.error, message: "JSON parsing error: \(error.localizedDescription)")
        }
    }
    
    func send(text: String) {
        guard isConnected else {
            log(.error, message: "Cannot send message: WebSocket not connected")
            return
        }
        
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                self?.log(.error, message: "Error sending WebSocket message: \(error.localizedDescription)")
            }
        }
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else {
            log(.debug, message: "Cannot send audio: WebSocket not connected")
            return
        }
        
        guard let audioData = pcmBufferToData(buffer) else {
            log(.error, message: "Failed to convert audio buffer to data")
            return
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

