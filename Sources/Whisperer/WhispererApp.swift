import SwiftUI
import AVFoundation
import AVKit

@main
struct WhispererApp: App {
    @StateObject private var statusBarController = StatusBarController()
    @State private var showingSettings = false
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(statusBarController)
        } label: {
            // Use the dynamic icon based on recording state
            Image(systemName: statusBarController.getStatusIcon())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusBarController.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
        
        // Add a settings window
        Settings {
            SettingsView(isPresented: $showingSettings)
        }
    }
    
    init() {
        // Request necessary permissions on app launch
        requestPermissions()
    }
    
    private func requestPermissions() {
        // For macOS, we don't need explicit microphone permission request
        // as that will be handled when we first use the microphone
        print("App initialized, permissions will be requested when needed.")
        
        // We can't programmatically request accessibility access,
        // so we'll show a prompt in the UI
    }
} 