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
            SettingsView()
                .frame(width: 300, height: 200)
        }
    }
}

struct SettingsView: View {
    @AppStorage("openAIApiKey") private var apiKey: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.headline)
            
            VStack(alignment: .leading) {
                Text("OpenAI API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
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
    }
}

#Preview {
    ContentView()
        .environmentObject(StatusBarController())
} 