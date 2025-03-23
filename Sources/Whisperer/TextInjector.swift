import Foundation
import Cocoa
import Carbon

class TextInjector {
    // Previous text to avoid reinserting the same content
    private var previousText = ""
    // For logging
    private let logEnabled = false
    
    func injectText(_ text: String) {
        // Handle delta updates vs. full text
        let newText: String
        
        // Only inject new text (the part that hasn't been injected yet)
        if text.hasPrefix(previousText) && !previousText.isEmpty {
            // If we already injected some of this text, only inject the new part
            newText = String(text.dropFirst(previousText.count))
            // Update the previous text to include the new text
            previousText = text
        } else if text.count < previousText.count || !text.contains(previousText) {
            // If text is shorter or doesn't contain previous text, it's likely a new utterance
            newText = text
            previousText = text
        } else {
            // Otherwise inject all of it
            newText = text
            previousText = text
        }
        
        // Do nothing if there's no new text
        guard !newText.isEmpty else { 
            log("No new text to inject")
            return 
        }
        
        log("Injecting text: \"\(newText)\"")
        
        // Inject the text using CGEvent.keyboardSetUnicodeString
        injectUnicodeString(newText)
    }
    
    private func injectUnicodeString(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log("Failed to create event source")
            return
        }
        
        // For longer texts, split and inject in chunks to avoid overwhelming the system
        let maxChunkSize = 20 // Maximum characters per event
        var remainingText = text
        
        while !remainingText.isEmpty {
            // Take the next chunk of text
            let endIndex = remainingText.index(remainingText.startIndex, offsetBy: min(maxChunkSize, remainingText.count))
            let chunk = String(remainingText[remainingText.startIndex..<endIndex])
            
            // Remove the chunk from the remaining text
            remainingText = String(remainingText[endIndex...])
            
            // Create key down event (we'll use keycode 0 since we're setting unicode string)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            
            // Convert the string to Unicode characters
            if let unicodeChars = chunk.unicodeScalars.map({ UniChar($0.value) }) as [UniChar]? {
                // Use the instance method to set Unicode string
                keyDown?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: unicodeChars)
                
                // Post the event
                keyDown?.post(tap: .cghidEventTap)
                
                // Create and post key up event
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                keyUp?.post(tap: .cghidEventTap)
            }
            
            // Add a small delay between chunks
            if !remainingText.isEmpty {
                usleep(5000) // 5ms delay between chunks
            }
        }
    }
    
    func reset() {
        previousText = ""
    }
    
    private func log(_ message: String) {
        if logEnabled {
            print("[TextInjector] \(message)")
        }
    }
} 


