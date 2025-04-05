import SwiftUI
import AVFoundation
import AVKit

@main
struct VoibeApp: App {
    @StateObject private var statusBarController = StatusBarController()
    @State private var showingSettings = false
    
    // For manual animation compatible with older macOS versions
    @State private var isBlinking = false
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    
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
            // Use the dynamic icon based on app state
            Group {
                if statusBarController.connectionState == "Transcribing" {
                    // Version-adaptive icon for transcribing state
                    transcribingIcon
                        .opacity(isBlinking ? 0.6 : 1.0)
                        .onReceive(timer) { _ in
                            // Only animate when in transcribing state
                            if statusBarController.connectionState == "Transcribing" {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isBlinking.toggle()
                                }
                            } else {
                                // Reset to full opacity when not transcribing
                                isBlinking = false
                            }
                        }
                } else {
                    // Standard icon for other states
                    Image(systemName: statusBarController.getStatusIcon())
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(getIconColor())
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        // Settings can now be accessed through the main view
        // We'll retain this for system-wide settings menu access
        Settings {
            Text("Settings are available directly from the app's menu bar icon.")
                .frame(width: 300, height: 100)
        }
    }
    
    // Version-adaptive implementation of the transcribing icon
    private var transcribingIcon: some View {
        Image(systemName: statusBarController.getStatusIcon())
            .symbolRenderingMode(.multicolor)
            .foregroundStyle(.blue)
    }
    
    private func getIconColor() -> Color {
        if statusBarController.isRecording {
            return .red
        } else {
            return .primary
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