import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var statusController: StatusBarController
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Whisperer")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showingSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(statusController.isRecording ? Color.red : Color.green)
                        .frame(width: 10, height: 10)
                    
                    Text(statusController.isRecording ? "Recording..." : "Ready")
                        .font(.subheadline)
                }
                
                Text("Hold **Right Option** to record")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if !statusController.lastTranscribedText.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcription:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(statusController.lastTranscribedText)
                        .font(.body)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
                .frame(width: 300, height: 350)
        }
    }
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("openAIApiKey") private var apiKey: String = ""
    @AppStorage("customPrompt") private var customPrompt: String = ""
    @State private var apiKeyMessage: String = ""
    @State private var apiKeyMessageColor: Color = .secondary
    @State private var isTesting = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            VStack(alignment: .leading) {
                Text("OpenAI API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { newValue in
                        validateApiKey(newValue)
                    }
                
                HStack {
                    if !apiKeyMessage.isEmpty {
                        Text(apiKeyMessage)
                            .font(.caption)
                            .foregroundColor(apiKeyMessageColor)
                    }
                    
                    Spacer()
                    
                    Button(action: testApiKey) {
                        Text("Test")
                            .frame(minWidth: 60)
                    }
                    .disabled(apiKey.isEmpty || isTesting)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .overlay {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading) {
                Text("Custom Prompt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customPrompt)
                    .font(.body)
                    .border(Color.secondary.opacity(0.3), width: 1)
                    .frame(height: 100)
                    .cornerRadius(4)
                
                Text("This prompt is sent to the transcription model for better context.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Accessibility permission is required for key monitoring and text injection.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding()
        .onAppear {
            validateApiKey(apiKey)
        }
    }
    
    private func validateApiKey(_ key: String) {
        if key.isEmpty {
            apiKeyMessage = "Enter your OpenAI API key to use the transcription service."
            apiKeyMessageColor = .secondary
        } else if !key.hasPrefix("sk-") {
            apiKeyMessage = "Warning: API key should start with 'sk-'"
            apiKeyMessageColor = .orange
        } else if key.count < 20 {
            apiKeyMessage = "Warning: API key seems too short"
            apiKeyMessageColor = .orange
        } else {
            apiKeyMessage = "API key format looks valid"
            apiKeyMessageColor = .green
        }
    }
    
    private func testApiKey() {
        isTesting = true
        apiKeyMessage = "Testing connection..."
        apiKeyMessageColor = .secondary
        
        // Create a URL for a simple API test (models endpoint is lightweight)
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isTesting = false
                
                if let error = error {
                    apiKeyMessage = "Connection error: \(error.localizedDescription)"
                    apiKeyMessageColor = .red
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    apiKeyMessage = "Invalid response"
                    apiKeyMessageColor = .red
                    return
                }
                
                switch httpResponse.statusCode {
                case 200:
                    apiKeyMessage = "✓ API key verified successfully"
                    apiKeyMessageColor = .green
                case 401:
                    apiKeyMessage = "✗ Invalid API key"
                    apiKeyMessageColor = .red
                case 429:
                    apiKeyMessage = "Rate limit exceeded. Try again later."
                    apiKeyMessageColor = .orange
                default:
                    apiKeyMessage = "Error: HTTP \(httpResponse.statusCode)"
                    apiKeyMessageColor = .red
                }
            }
        }
        
        task.resume()
    }
}

#Preview {
    ContentView()
        .environmentObject(StatusBarController())
} 