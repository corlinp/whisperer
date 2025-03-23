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
                // Fix for menu bar closing when clicking inside
                .onTapGesture {
                    // This empty gesture interceptor prevents propagation of 
                    // tap events to the parent view which would close the menu
                }
        } label: {
            // Use the dynamic icon based on recording state
            Image(systemName: statusBarController.getStatusIcon())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusBarController.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
        
        // Settings can now be accessed through the main view
        // We'll retain this for system-wide settings menu access
        Settings {
            Text("Settings are available directly from the app's menu bar icon.")
                .frame(width: 300, height: 100)
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
    }
} 