import SwiftUI

@main
struct WhispererApp: App {
    @StateObject private var statusBarController = StatusBarController()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
} 