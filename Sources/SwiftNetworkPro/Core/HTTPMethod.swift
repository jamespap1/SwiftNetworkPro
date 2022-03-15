import Foundation

/// HTTP methods supported by SwiftNetwork Pro
public enum HTTPMethod: String, CaseIterable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"
    
    /// Indicates whether the method typically has a request body
    public var hasBody: Bool {
        switch self {
        case .post, .put, .patch:
            return true
        default:
            return false
        }
    }
    
    /// Indicates whether the method is safe (doesn't modify server state)
    public var isSafe: Bool {
        switch self {
        case .get, .head, .options, .trace:
            return true
        default:
            return false
        }
    }
    
    /// Indicates whether the method is idempotent
    public var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete, .head, .options, .trace:
            return true
        default:
            return false
        }
    }
    
    /// Indicates whether the method is cacheable by default
    public var isCacheable: Bool {
        switch self {
        case .get, .head:
            return true
        case .post:
            // POST can be cacheable with proper headers
            return false
        default:
            return false
        }
    }
}