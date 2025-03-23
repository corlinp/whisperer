import Foundation
import SystemConfiguration

class Reachability {
    
    enum Connection: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unavailable = "No Connection"
    }
    
    var connection: Connection {
        var flags = SCNetworkReachabilityFlags()
        let isReachable = checkReachability(&flags)
        
        if !isReachable {
            return .unavailable
        }
        
        #if os(iOS)
        if flags.contains(.isWWAN) {
            return .cellular
        }
        #endif
        
        return .wifi
    }
    
    func checkReachability(_ flags: UnsafeMutablePointer<SCNetworkReachabilityFlags>) -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        let result = SCNetworkReachabilityGetFlags(reachability, flags)
        
        return result
    }
    
    init() throws {}
} 