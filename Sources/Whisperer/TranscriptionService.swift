import Foundation
import AVFoundation

// Extension to allow easy conversion of integers to Data
extension FixedWidthInteger {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
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
            DispatchQueue.main.async {
                self.onConnectionStateChanged?(self.connectionState)
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
    
    // Start recording
    func startRecording() {
        log(.info, message: "Starting recording")
        connectionState = .recording
        recordedAudioData = nil
    }
    
    // Called when recording is finished
    func finishRecording(withAudioData audioData: Data) {
        log(.info, message: "Recording finished, sending audio for transcription")
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
        
        // Create a data task for the request with streaming support
        let session = URLSession.shared
        transcriptionTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log(.error, message: "Transcription request failed: \(error.localizedDescription)")
                self.connectionState = .error("Request failed: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.connectionState = .error("Invalid response from server")
                return
            }
            
            if httpResponse.statusCode != 200 {
                let errorMessage = self.parseErrorMessage(data: data)
                self.log(.error, message: "Server returned error: \(httpResponse.statusCode), \(errorMessage)")
                self.connectionState = .error("Server error: \(httpResponse.statusCode)")
                return
            }
            
            guard let data = data else {
                self.connectionState = .error("No data received")
                return
            }
            
            self.log(.info, message: "Transcription data received, processing SSE response")
            
            // Process the SSE data
            self.handleSSEData(data)
            
            // Mark as complete
            self.log(.info, message: "Transcription complete")
            self.connectionState = .idle
        }
        
        transcriptionTask?.resume()
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
            return
        }
        
        // Split the string by double newlines, which separate SSE messages
        let eventStrings = sseText.components(separatedBy: "\n\n")
        
        for eventString in eventStrings {
            if eventString.isEmpty { continue }
            
            // Extract the JSON from lines that start with "data: "
            for line in eventString.components(separatedBy: "\n") {
                if line.hasPrefix("data: ") {
                    let jsonText = String(line.dropFirst(6))
                    processSSEEvent(jsonText)
                }
            }
        }
    }
    
    // Process a single SSE event
    private func processSSEEvent(_ jsonText: String) {
        // Skip empty messages and special non-JSON messages
        if jsonText.isEmpty || jsonText == "[DONE]" {
            log(.debug, message: "Received end-of-stream marker")
            return
        }
        
        guard let jsonData = jsonText.data(using: .utf8) else { 
            log(.debug, message: "Could not convert SSE text to data")
            return 
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let type = json["type"] as? String {
                
                switch type {
                case "transcript.text.delta":
                    if let delta = json["delta"] as? String {
                        log(.debug, message: "Transcription delta: \"\(delta)\"")
                        DispatchQueue.main.async {
                            self.onTranscriptionReceived?(delta)
                        }
                    }
                    
                case "transcript.text.done":
                    if let fullText = json["text"] as? String {
                        log(.info, message: "Transcription complete: \"\(fullText)\"")
                    }
                    
                default:
                    log(.debug, message: "Unhandled SSE event type: \(type)")
                }
            }
        } catch {
            // Don't treat as an error - this could be a non-JSON message or stream terminator
            log(.debug, message: "Skipping non-JSON SSE message: \(error.localizedDescription)")
        }
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
        connectionState = .idle
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

