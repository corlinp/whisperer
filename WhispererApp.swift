import SwiftUI

@main
struct WhispererApp: App {
    @StateObject private var statusBarController = StatusBarController()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(statusBarController)
        } label: {
            Image(systemName: statusBarController.getStatusIcon())
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: statusBarController.connectionState) { _ in
            // Force refresh when state changes to update icon in menu bar
            NSApplication.shared.windows.first?.contentView?.needsDisplay = true
        }
    }
} 