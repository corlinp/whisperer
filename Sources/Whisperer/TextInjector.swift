import Foundation
import Cocoa
import Carbon

class TextInjector {
    // Previous text to avoid reinserting the same content
    private var previousText = ""
    
    func injectText(_ text: String) {
        // Only inject new text (the part that hasn't been injected yet)
        guard text != previousText else { return }
        
        let newText: String
        if text.hasPrefix(previousText) && !previousText.isEmpty {
            // If we already injected some of this text, only inject the new part
            newText = String(text.dropFirst(previousText.count))
        } else {
            // Otherwise inject all of it
            newText = text
        }
        
        // Do nothing if there's no new text
        guard !newText.isEmpty else { return }
        
        // Save the full text for future comparisons
        previousText = text
        
        // Inject the text by simulating keyboard events
        simulateTyping(newText)
    }
    
    private func simulateTyping(_ text: String) {
        // Ensure we can create an event source for keyboard events
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            print("Failed to create event source")
            return
        }
        
        for char in text {
            insertChar(char, source: eventSource)
        }
    }
    
    private func insertChar(_ char: Character, source: CGEventSource) {
        var keyCode: CGKeyCode = 0
        var needsShift = false
        
        // Map character to key code and shift state
        switch char {
        case "a": keyCode = 0
        case "s": keyCode = 1
        case "d": keyCode = 2
        case "f": keyCode = 3
        case "h": keyCode = 4
        case "g": keyCode = 5
        case "z": keyCode = 6
        case "x": keyCode = 7
        case "c": keyCode = 8
        case "v": keyCode = 9
        case "b": keyCode = 11
        case "q": keyCode = 12
        case "w": keyCode = 13
        case "e": keyCode = 14
        case "r": keyCode = 15
        case "y": keyCode = 16
        case "t": keyCode = 17
        case "1", "!": keyCode = 18; needsShift = (char == "!")
        case "2", "@": keyCode = 19; needsShift = (char == "@")
        case "3", "#": keyCode = 20; needsShift = (char == "#")
        case "4", "$": keyCode = 21; needsShift = (char == "$")
        case "6", "^": keyCode = 22; needsShift = (char == "^")
        case "5", "%": keyCode = 23; needsShift = (char == "%")
        case "=", "+": keyCode = 24; needsShift = (char == "+")
        case "9", "(": keyCode = 25; needsShift = (char == "(")
        case "7", "&": keyCode = 26; needsShift = (char == "&")
        case "-", "_": keyCode = 27; needsShift = (char == "_")
        case "8", "*": keyCode = 28; needsShift = (char == "*")
        case "0", ")": keyCode = 29; needsShift = (char == ")")
        case "]", "}": keyCode = 30; needsShift = (char == "}")
        case "o": keyCode = 31
        case "u": keyCode = 32
        case "[", "{": keyCode = 33; needsShift = (char == "{")
        case "i": keyCode = 34
        case "p": keyCode = 35
        case "l": keyCode = 37
        case "j": keyCode = 38
        case "'", "\"": keyCode = 39; needsShift = (char == "\"")
        case "k": keyCode = 40
        case ";", ":": keyCode = 41; needsShift = (char == ":")
        case "\\", "|": keyCode = 42; needsShift = (char == "|")
        case ",", "<": keyCode = 43; needsShift = (char == "<")
        case "/", "?": keyCode = 44; needsShift = (char == "?")
        case "n": keyCode = 45
        case "m": keyCode = 46
        case ".", ">": keyCode = 47; needsShift = (char == ">")
        case " ": keyCode = 49 // Space
        case "\n", "\r": keyCode = 36 // Return
        case "\t": keyCode = 48 // Tab
        case "A": keyCode = 0; needsShift = true
        case "B": keyCode = 11; needsShift = true
        case "C": keyCode = 8; needsShift = true
        case "D": keyCode = 2; needsShift = true
        case "E": keyCode = 14; needsShift = true
        case "F": keyCode = 3; needsShift = true
        case "G": keyCode = 5; needsShift = true
        case "H": keyCode = 4; needsShift = true
        case "I": keyCode = 34; needsShift = true
        case "J": keyCode = 38; needsShift = true
        case "K": keyCode = 40; needsShift = true
        case "L": keyCode = 37; needsShift = true
        case "M": keyCode = 46; needsShift = true
        case "N": keyCode = 45; needsShift = true
        case "O": keyCode = 31; needsShift = true
        case "P": keyCode = 35; needsShift = true
        case "Q": keyCode = 12; needsShift = true
        case "R": keyCode = 15; needsShift = true
        case "S": keyCode = 1; needsShift = true
        case "T": keyCode = 17; needsShift = true
        case "U": keyCode = 32; needsShift = true
        case "V": keyCode = 9; needsShift = true
        case "W": keyCode = 13; needsShift = true
        case "X": keyCode = 7; needsShift = true
        case "Y": keyCode = 16; needsShift = true
        case "Z": keyCode = 6; needsShift = true
        default:
            print("Character not supported: \(char)")
            return
        }
        
        var keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        var keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        if needsShift {
            // Shift key down
            let shiftDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: true)
            shiftDownEvent?.post(tap: .cghidEventTap)
            
            // Key with shift pressed
            keyDownEvent?.post(tap: .cghidEventTap)
            keyUpEvent?.post(tap: .cghidEventTap)
            
            // Shift key up
            let shiftUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: false)
            shiftUpEvent?.post(tap: .cghidEventTap)
        } else {
            // Key without shift
            keyDownEvent?.post(tap: .cghidEventTap)
            keyUpEvent?.post(tap: .cghidEventTap)
        }
        
        // Small delay to avoid overwhelming the system
        usleep(1000) // 1ms delay
    }
    
    func reset() {
        previousText = ""
    }
} 