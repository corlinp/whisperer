import Foundation
import AVFoundation

class TranscriptionService {
    // WebSocket connection for streaming audio and receiving transcriptions
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    
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
        
        // Skip reachability check for now since we don't have the Swift flag properly set
        /*
        let reachability = try? Reachability()
        if reachability?.connection == .unavailable {
            print("Error: No internet connection available")
        } else {
            print("Internet connection is available")
        }
        */
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            print("Error: Invalid URL for OpenAI WebSocket")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Add required beta header for the Realtime API
        request.setValue("realtime=v1", forHTTPHeaderField: "openai-beta")
        request.timeoutInterval = 30 // Increase timeout for better chance of connection
        
        print("Creating WebSocket connection...")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        // Set up a ping task to keep connection alive
        setupPingTask()
        
        // Start receiving messages
        receiveMessages()
        
        print("Starting WebSocket connection...")
        webSocketTask?.resume()
        
        // Configure the transcription session
        let configMessage = """
        {
          "type": "transcription_session.update",
          "input_audio_format": "pcm16",
          "input_audio_transcription": {
            "model": "gpt-4o-transcribe",
            "prompt": "\(customPrompt.replacingOccurrences(of: "\"", with: "\\\""))",
            "language": ""
          },
          "turn_detection": {
            "type": "server_vad",
            "threshold": 0.5,
            "prefix_padding_ms": 300,
            "silence_duration_ms": 500
          },
          "input_audio_noise_reduction": {
            "type": "near_field"
          }
        }
        """
        
        // Wait a short time to ensure connection is established before sending the config
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("Sending configuration message: \(configMessage)")
            self.send(text: configMessage)
            self.isConnected = true
            print("WebSocket connection established and configured")
        }
    }
    
    func disconnect() {
        print("Disconnecting WebSocket...")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
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
                        print("Ping successful")
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }
    
    private func receiveMessages() {
        print("Starting to receive WebSocket messages...")
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                print("Received WebSocket message")
                switch message {
                case .string(let text):
                    print("Received text message: \(text)")
                    self.handleReceivedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("Received data message: \(text)")
                        self.handleReceivedMessage(text)
                    } else {
                        print("Received binary data of size: \(data.count)")
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
            
            print("Parsed JSON message: \(json)")
            
            // Handle transcription results based on the API response format
            if let type = json["type"] as? String {
                print("Message type: \(type)")
                
                if type == "transcription.item.update",
                   let item = json["item"] as? [String: Any],
                   let transcription = item["input_audio_transcription"] as? [String: Any],
                   let text = transcription["text"] as? String {
                    
                    print("Transcription received: \(text)")
                    DispatchQueue.main.async {
                        self.onTranscriptionReceived?(text)
                    }
                } else if type == "error" {
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("API error: \(message)")
                    } else {
                        print("Unknown error format in message")
                    }
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
        
        print("Sending message: \(text)")
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("Error sending WebSocket message: \(error.localizedDescription)")
            } else {
                print("Message sent successfully")
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
        
        // Create the audio buffer append message
        let message = """
        {
          "type": "input_audio_buffer.append",
          "audio": "\(base64Audio)"
        }
        """
        
        // Log only a summary to avoid flooding the console
        print("Sending audio buffer: \(audioData.count) bytes")
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