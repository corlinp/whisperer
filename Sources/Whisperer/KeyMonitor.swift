import Cocoa
import Carbon

class KeyMonitor {
    // Key code for right option key is 61
    fileprivate let rightOptionKeyCode: Int = 61
    
    fileprivate var isRightOptionPressed = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    var onRightOptionKeyDown: (() -> Void)?
    var onRightOptionKeyUp: (() -> Void)?
    
    init() {}
    
    deinit {
        stop()
    }
    
    func start() {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // For C callbacks we can't use a closure that captures context directly
        // So we'll use a static callback function and pass self as userInfo
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passRetained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("Key monitor started")
        }
    }
    
    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        
        print("Key monitor stopped")
    }
}

// Static callback function for the event tap
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    // Get the KeyMonitor instance from userInfo
    let keyMonitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    
    if type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if keyCode == keyMonitor.rightOptionKeyCode {
            let flags = event.flags
            let isOptionPressed = flags.contains(.maskAlternate)
            
            if isOptionPressed && !keyMonitor.isRightOptionPressed {
                keyMonitor.isRightOptionPressed = true
                DispatchQueue.main.async {
                    keyMonitor.onRightOptionKeyDown?()
                }
            } else if !isOptionPressed && keyMonitor.isRightOptionPressed {
                keyMonitor.isRightOptionPressed = false
                DispatchQueue.main.async {
                    keyMonitor.onRightOptionKeyUp?()
                }
            }
        }
    }
    
    return Unmanaged.passRetained(event)
} 