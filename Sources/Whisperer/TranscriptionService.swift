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
    
    init() {}
    
    func connect() {
        guard apiKey.isEmpty == false else {
            print("Error: OpenAI API key is not set")
            return
        }
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            print("Error: Invalid URL for OpenAI WebSocket")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        // Set up a ping task to keep connection alive
        setupPingTask()
        
        // Start receiving messages
        receiveMessages()
        
        webSocketTask?.resume()
        
        // Configure the transcription session
        let configMessage = """
        {
          "type": "transcription_session.update",
          "input_audio_format": "pcm16",
          "input_audio_transcription": {
            "model": "gpt-4o-transcribe",
            "prompt": "",
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
        
        send(text: configMessage)
        isConnected = true
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("WebSocket disconnected")
    }
    
    private func setupPingTask() {
        // Use _ to discard the task but keep it running
        _ = Task {
            while isConnected && webSocketTask != nil {
                webSocketTask?.sendPing { error in
                    if let error = error {
                        print("Ping error: \(error.localizedDescription)")
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
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving messages
                self.receiveMessages()
                
            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                self.isConnected = false
            }
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Handle transcription results based on the API response format
        if let type = json["type"] as? String, type == "transcription.item.update",
           let item = json["item"] as? [String: Any],
           let transcription = item["input_audio_transcription"] as? [String: Any],
           let text = transcription["text"] as? String {
            
            DispatchQueue.main.async {
                self.onTranscriptionReceived?(text)
            }
        }
    }
    
    func send(text: String) {
        guard isConnected else { return }
        
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("Error sending WebSocket message: \(error.localizedDescription)")
            }
        }
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected, let audioData = pcmBufferToData(buffer) else { return }
        
        // Convert audio data to base64
        let base64Audio = audioData.base64EncodedString()
        
        // Create the audio buffer append message
        let message = """
        {
          "type": "input_audio_buffer.append",
          "audio": "\(base64Audio)"
        }
        """
        
        send(text: message)
    }
    
    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        
        let frameLength = Int(buffer.frameLength)
        
        // For simplicity, we'll just use the first channel if it's stereo
        let audioBuffer = channelData[0]
        
        return Data(bytes: audioBuffer, count: frameLength * 2) // 2 bytes per Int16 sample
    }
} 