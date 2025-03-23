import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var statusController: StatusBarController
    @AppStorage("openAIApiKey") private var apiKey: String = ""
    @AppStorage("customPrompt") private var customPrompt: String = ""
    @State private var apiKeyMessage: String = ""
    @State private var apiKeyMessageColor: Color = .secondary
    @State private var isTesting = false
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Whisperer")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: showSettings ? "chevron.down" : "gear")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help(showSettings ? "Hide settings" : "Show settings")
            }
            
            Divider()
            
            // Status section
            StatusSection(
                isRecording: statusController.isRecording,
                connectionState: statusController.connectionState
            )
            
            // Last transcription (if any)
            if !statusController.lastTranscribedText.isEmpty {
                Divider()
                LastTranscriptionSection(text: statusController.lastTranscribedText)
            }
            
            // Settings section (collapsible)
            if showSettings {
                Divider()
                SettingsSection(
                    apiKey: $apiKey,
                    customPrompt: $customPrompt,
                    apiKeyMessage: $apiKeyMessage,
                    apiKeyMessageColor: $apiKeyMessageColor,
                    isTesting: $isTesting
                )
            }
            
            Spacer()
            
            // Quit button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            validateApiKey(apiKey)
        }
    }
    
    private func validateApiKey(_ key: String) {
        if key.isEmpty {
            apiKeyMessage = "Enter your OpenAI API key"
            apiKeyMessageColor = .secondary
        } else if !key.hasPrefix("sk-") {
            apiKeyMessage = "API key should start with 'sk-'"
            apiKeyMessageColor = .orange
        } else if key.count < 20 {
            apiKeyMessage = "API key seems too short"
            apiKeyMessageColor = .orange
        } else {
            apiKeyMessage = "API key format looks valid"
            apiKeyMessageColor = .green
        }
    }
}

// MARK: - Subviews

struct StatusSection: View {
    let isRecording: Bool
    let connectionState: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(statusText)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            
            Text("Hold **Right Option** to record")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        if isRecording {
            return .red
        } else if connectionState == "Transcribing" {
            return .blue
        } else if connectionState == "Recording" {
            return .orange
        } else if connectionState == "Error" {
            return .red
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        if isRecording {
            return "Recording..."
        } else if connectionState == "Transcribing" {
            return "Transcribing..."
        } else if connectionState == "Recording" {
            return "Recording..."
        } else if connectionState == "Error" {
            return "Error"
        } else {
            return "Ready"
        }
    }
}

struct LastTranscriptionSection: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Transcription")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsSection: View {
    @Binding var apiKey: String
    @Binding var customPrompt: String
    @Binding var apiKeyMessage: String
    @Binding var apiKeyMessageColor: Color
    @Binding var isTesting: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.top, 4)
            
            // API Key
            VStack(alignment: .leading, spacing: 4) {
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
            
            // Custom Prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Prompt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customPrompt)
                    .font(.body)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .frame(height: 80)
                
                Text("Add context to improve transcription accuracy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Accessibility settings
            VStack(spacing: 6) {
                Text("Accessibility permission is required for key monitoring")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
    
    private func validateApiKey(_ key: String) {
        if key.isEmpty {
            apiKeyMessage = "Enter your OpenAI API key"
            apiKeyMessageColor = .secondary
        } else if !key.hasPrefix("sk-") {
            apiKeyMessage = "API key should start with 'sk-'"
            apiKeyMessageColor = .orange
        } else if key.count < 20 {
            apiKeyMessage = "API key seems too short"
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