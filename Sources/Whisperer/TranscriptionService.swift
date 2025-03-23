import Foundation
import AVFoundation

class TranscriptionService {
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
            print("Error: OpenAI API key is not set")
            return
        }
        
        if !apiKey.hasPrefix("sk-") {
            print("Warning: API key does not start with 'sk-'. This may not be a valid OpenAI API key.")
        }
        
        print("Connecting to OpenAI Realtime API with API key: \(apiKey.prefix(5))...")
        
        // Create a transcription session first
        createTranscriptionSession()
    }
    
    private func createTranscriptionSession() {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/transcription_sessions") else {
            print("Error: Invalid URL for OpenAI API")
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
            print("Error serializing session config: \(error.localizedDescription)")
            return
        }
        
        // Create session
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error creating transcription session: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Error: No HTTP response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                print("Error: HTTP status code \(httpResponse.statusCode)")
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("Error response: \(errorString)")
                    if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Error response: \(errorResponse)")
                    }
                }
                return
            }
            
            guard let data = data else {
                print("Error: No data received")
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("Error parsing session response: Not a dictionary")
                    return
                }
                
                if let id = json["id"] as? String {
                    print("Transcription session created with ID: \(id)")
                    self.sessionId = id
                    
                    // Extract client secret for WebSocket authentication
                    if let clientSecret = json["client_secret"] as? [String: Any],
                       let clientSecretValue = clientSecret["value"] as? String {
                        print("Client secret obtained: \(clientSecretValue.prefix(5))...")
                        self.clientSecret = clientSecretValue
                        self.connectWebSocket()
                    } else {
                        print("Error: No client_secret in response")
                    }
                } else {
                    print("Error: No session ID in response")
                    if let errorObj = json["error"] as? [String: Any], let message = errorObj["message"] as? String {
                        print("API error: \(message)")
                    }
                }
            } catch {
                print("Error parsing session response: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    private func connectWebSocket() {
        guard let sessionId = sessionId, let clientSecret = clientSecret else {
            print("Error: Session ID or client secret not available")
            return
        }
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            print("Error: Invalid URL for OpenAI WebSocket")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.timeoutInterval = 30
        
        print("Creating WebSocket connection...")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        // Set up a ping task to keep connection alive
        setupPingTask()
        
        // Start receiving messages
        receiveMessages()
        
        print("Starting WebSocket connection...")
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
        
        // print("Sending transcription session update")
        send(text: updateMessage)
    }
    
    func disconnect() {
        print("Disconnecting WebSocket...")
        isConnected = false  // Set this first to prevent further processing
        
        // Cancel any pending receive operations
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionId = nil
        clientSecret = nil
        print("WebSocket disconnected")
    }
    
    private func setupPingTask() {
        print("Setting up ping task to maintain connection...")
        // Use _ to discard the task but keep it running
        _ = Task {
            while isConnected && webSocketTask != nil {
                print("Sending WebSocket ping...")
                webSocketTask?.sendPing { error in
                    if let error = error {
                        print("Ping error: \(error.localizedDescription)")
                    } else {
                        // print("Ping successful")
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }
    
    private func receiveMessages() {
        // print("Starting to receive WebSocket messages...")
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // print("Received text message")
                    self.handleReceivedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        // print("Received data message")
                        self.handleReceivedMessage(text)
                    } else {
                        // print("Received binary data of size: \(data.count)")
                    }
                @unknown default:
                    print("Received unknown message type")
                    break
                }
                
                // Continue receiving messages
                self.receiveMessages()
                
            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                print("Error code: \(error._code), domain: \(error._domain)")
                print("Connection state: \(self.isConnected ? "Connected" : "Disconnected")")
                self.isConnected = false
            }
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else {
            print("Failed to convert message to data")
            return
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse JSON: Not a dictionary")
                return
            }
            
            if let type = json["type"] as? String {
                // print("Message type: \(type)")
                
                switch type {
                case "transcription_session.created":
                    if let session = json["session"] as? [String: Any], 
                       let id = session["id"] as? String {
                        print("Transcription session created with ID: \(id)")
                        sessionId = id
                    }
                
                case "input_audio_buffer.speech_started":
                    print("Speech detected - beginning transcription...")
                    if let itemId = json["item_id"] as? String {
                        print("Speech started with item ID: \(itemId)")
                    }
                
                case "conversation.item.input_audio_transcription.completed":
                    // Handle complete transcription in the format from the API docs
                    if let transcript = json["transcript"] as? String {
                        print("Complete transcription received: \"\(transcript)\"")
                        DispatchQueue.main.async {
                            self.onTranscriptionReceived?(transcript)
                        }
                    }
                    
                case "conversation.item.input_audio_transcription.delta":
                    // Handle incremental text updates in the format from the API docs
                    if let delta = json["delta"] as? String {
                        print("Transcription delta received: \"\(delta)\"")
                        DispatchQueue.main.async {
                            self.onTranscriptionReceived?(delta)
                        }
                    }
                    
                case "error":
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("API error: \(message)")
                        if let code = error["code"] as? String {
                            print("Error code: \(code)")
                        }
                    } else {
                        print("Unknown error format in message")
                    }
                    
                case "input_audio_buffer.speech_stopped":
                    print("Speech ended")
                    // Handle speech end events if needed
                    
                case "input_audio_buffer.committed":
                    if let itemId = json["item_id"] as? String {
                        // print("Audio buffer committed for item: \(itemId)")
                    }
                    
                case "conversation.item.created":
                    if let item = json["item"] as? [String: Any], 
                       let itemId = item["id"] as? String {
                        // print("Conversation item created with ID: \(itemId)")
                    }
                    
                default:
                    print("Unhandled message type: \(type)")
                    print("Message content: \(json)")
                }
            }
        } catch {
            print("JSON parsing error: \(error.localizedDescription)")
        }
    }
    
    func send(text: String) {
        guard isConnected else {
            print("Cannot send message: WebSocket not connected")
            return
        }
        
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("Error sending WebSocket message: \(error.localizedDescription)")
            } else {
                // print("Message sent successfully")
            }
        }
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else {
            print("Cannot send audio: WebSocket not connected")
            return
        }
        
        guard let audioData = pcmBufferToData(buffer) else {
            print("Failed to convert audio buffer to data")
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
        
        // Log only a summary to avoid flooding the console
        // print("Sending audio buffer: \(audioData.count) bytes")
        send(text: message)
    }
    
    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            print("No int16ChannelData in buffer")
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        
        // For simplicity, we'll just use the first channel if it's stereo
        let audioBuffer = channelData[0]
        
        return Data(bytes: audioBuffer, count: frameLength * 2) // 2 bytes per sample for Int16
    }
} 

