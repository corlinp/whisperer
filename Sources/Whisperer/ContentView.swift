import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var statusController: StatusBarController
    @AppStorage("openAIApiKey") private var apiKey: String = ""
    @AppStorage("customPrompt") private var customPrompt: String = ""
    @AppStorage("totalTranscriptions") private var totalTranscriptions: Int = 0
    @AppStorage("totalTimeTranscribedSeconds") private var totalTimeTranscribedSeconds: Double = 0
    @State private var apiKeyMessage: String = ""
    @State private var apiKeyMessageColor: Color = .secondary
    @State private var isTesting = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Whisperer")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Quit button moved to top right
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            // Status section
            StatusSection(
                isRecording: statusController.isRecording,
                connectionState: statusController.connectionState,
                isToggleMode: statusController.isToggleMode
            )
            
            Divider()
            
            // Transcription history section
            TranscriptionHistorySection(
                currentText: statusController.lastTranscribedText,
                history: statusController.transcriptionHistory
            )
            
            Divider()
            
            // Usage metrics section
            UsageMetricsSection(
                totalTranscriptions: totalTranscriptions,
                totalTimeTranscribedSeconds: totalTimeTranscribedSeconds,
                onReset: resetMetrics
            )
            
            Divider()
            
            // Settings section (always shown)
            SettingsSection(
                apiKey: $apiKey,
                customPrompt: $customPrompt,
                apiKeyMessage: $apiKeyMessage,
                apiKeyMessageColor: $apiKeyMessageColor,
                isTesting: $isTesting
            )
            
            Spacer()
            
            // Footer with attribution and links
            HStack(spacing: 8) {
                Text("Created by Corlin Palmer, 2025")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Link("GitHub", destination: URL(string: "https://github.com/corlinp/whisperer")!)
                    .font(.caption2)
                
                Link("Website", destination: URL(string: "https://corlin.io/whisperer")!)
                    .font(.caption2)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            validateApiKey(apiKey)
            setupNotifications()
        }
        .onDisappear {
            removeNotifications()
        }
    }
    
    private func setupNotifications() {
        // Subscribe to transcription completed notifications
        NotificationCenter.default.addObserver(
            forName: .transcriptionCompleted,
            object: nil,
            queue: .main
        ) { notification in
            // Update metrics with the duration from notification
            if let duration = notification.userInfo?["duration"] as? Double {
                updateMetrics(duration: duration)
            } else {
                // If duration is missing for some reason, just increment count
                // with a minimal duration to ensure it's counted
                updateMetrics(duration: 0.1)
            }
        }
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self, name: .transcriptionCompleted, object: nil)
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
    
    private func updateMetrics(duration: Double) {
        // Only count transcriptions that are at least 0.5 seconds
        // This helps avoid counting accidental key presses
        if duration >= 0.5 {
            totalTranscriptions += 1
            totalTimeTranscribedSeconds += duration
            
            // AppStorage automatically triggers UI updates - no need for objectWillChange
        }
    }
    
    private func resetMetrics() {
        totalTranscriptions = 0
        totalTimeTranscribedSeconds = 0
        // AppStorage automatically triggers UI updates - no need for objectWillChange
    }
}

// MARK: - Subviews

struct StatusSection: View {
    let isRecording: Bool
    let connectionState: String
    let isToggleMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(statusText)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            
            if isToggleMode && isRecording {
                Text("Toggle mode active. Press **Right Option** again to stop")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(isToggleMode ? 
                     "Quick tap **Right Option** to toggle recording on/off" : 
                     "Hold **Right Option** to record")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Recording stops automatically after 5 minutes")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
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

struct TranscriptionHistorySection: View {
    let currentText: String
    let history: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription History")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Display current transcription if we're recording or transcribing 
            // but only if it's not already in the history
            if !currentText.isEmpty && (history.isEmpty || currentText != history[0]) {
                transcriptionRow(text: currentText, isCurrent: true)
            }
            
            // Display last three transcriptions
            ForEach(history.indices, id: \.self) { index in
                transcriptionRow(text: history[index], isCurrent: false)
            }
            
            // Show placeholder if no transcriptions
            if currentText.isEmpty && history.isEmpty {
                Text("No transcriptions yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func transcriptionRow(text: String, isCurrent: Bool) -> some View {
        HStack(alignment: .top) {
            // Show preview of text (first 30 chars or so)
            Text(previewText(text))
                .font(.body)
                .lineLimit(1)
                .foregroundColor(isCurrent ? .blue : .primary)
            
            Spacer()
            
            // Copy button
            Button(action: {
                copyToClipboard(text)
            }) {
                Image(systemName: "doc.on.doc")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 2)
    }
    
    private func previewText(_ text: String) -> String {
        if text.count <= 30 {
            return text
        } else {
            let index = text.index(text.startIndex, offsetBy: 30)
            return String(text[..<index]) + "..."
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct SettingsSection: View {
    @Binding var apiKey: String
    @Binding var customPrompt: String
    @Binding var apiKeyMessage: String
    @Binding var apiKeyMessageColor: Color
    @Binding var isTesting: Bool
    
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.primary)
            
            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenAI API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    if isEditing {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { newValue in
                                validateApiKey(newValue)
                            }
                            .onSubmit {
                                isEditing = false
                            }
                    } else {
                        Text(maskedApiKey)
                            .font(.body)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
                            .onTapGesture {
                                isEditing = true
                            }
                    }
                    
                    Button(action: {
                        isEditing.toggle()
                    }) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .help(isEditing ? "Save" : "Edit")
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
    
    private var maskedApiKey: String {
        if apiKey.isEmpty {
            return "No API key set"
        } else {
            // Show first 10 characters
            let visibleCount = min(10, apiKey.count)
            let visiblePart = apiKey.prefix(visibleCount)
            return "\(visiblePart)••••••••••••"
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

struct UsageMetricsSection: View {
    let totalTranscriptions: Int
    let totalTimeTranscribedSeconds: Double
    var onReset: () -> Void
    
    private var totalMinutes: Double {
        totalTimeTranscribedSeconds / 60.0
    }
    
    private var totalCost: Double {
        // $0.006 per minute
        totalMinutes * 0.006
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usage Metrics")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)
            }
            
            HStack(spacing: 20) {
                metricView(label: "Transcriptions", value: "\(totalTranscriptions)")
                metricView(label: "Time", value: timeFormatted)
                metricView(label: "Cost", value: costFormatted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    
    private func metricView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
    
    private var timeFormatted: String {
        if totalMinutes < 1 {
            return String(format: "%.0f sec", totalTimeTranscribedSeconds)
        } else {
            return String(format: "%.1f min", totalMinutes)
        }
    }
    
    private var costFormatted: String {
        return String(format: "$%.3f", totalCost)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(StatusBarController())
    }
}
#endif 