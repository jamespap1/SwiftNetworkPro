import Foundation

/// Comprehensive error types for SwiftNetwork Pro
public enum NetworkError: LocalizedError, Equatable {
    // MARK: - Connection Errors
    case noInternetConnection
    case connectionTimeout(TimeInterval)
    case connectionLost
    case cannotConnectToHost(String)
    
    // MARK: - Request Errors
    case invalidURL(String)
    case invalidRequest
    case requestCancelled
    case tooManyRequests(retryAfter: TimeInterval?)
    case payloadTooLarge(maxSize: Int)
    
    // MARK: - Response Errors
    case invalidResponse
    case noData
    case decodingFailed(Error)
    case encodingFailed(Error)
    case invalidStatusCode(Int, data: Data?)
    
    // MARK: - Server Errors
    case serverError(statusCode: Int, message: String?)
    case serviceUnavailable(retryAfter: TimeInterval?)
    case gatewayTimeout
    
    // MARK: - Authentication Errors
    case unauthorized(reason: String?)
    case forbidden
    case tokenExpired
    case invalidCredentials
    
    // MARK: - Security Errors
    case sslCertificateError(Error)
    case insecureConnection
    case certificatePinningFailed
    
    // MARK: - Cache Errors
    case cacheNotFound
    case cacheExpired
    case cacheCorrupted
    
    // MARK: - WebSocket Errors
    case webSocketConnectionFailed(Error)
    case webSocketDisconnected(code: Int, reason: String?)
    case webSocketInvalidMessage
    
    // MARK: - GraphQL Errors
    case graphQLError(errors: [GraphQLError])
    case graphQLValidationFailed(String)
    
    // MARK: - Unknown
    case unknown(Error)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            return "No internet connection available"
        case .connectionTimeout(let timeout):
            return "Connection timed out after \(timeout) seconds"
        case .connectionLost:
            return "Connection was lost"
        case .cannotConnectToHost(let host):
            return "Cannot connect to host: \(host)"
            
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidRequest:
            return "Invalid request configuration"
        case .requestCancelled:
            return "Request was cancelled"
        case .tooManyRequests(let retryAfter):
            if let retryAfter = retryAfter {
                return "Too many requests. Retry after \(retryAfter) seconds"
            }
            return "Too many requests. Please try again later"
        case .payloadTooLarge(let maxSize):
            return "Request payload too large. Maximum size: \(maxSize) bytes"
            
        case .invalidResponse:
            return "Invalid response received from server"
        case .noData:
            return "No data received from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .invalidStatusCode(let code, _):
            return "Invalid status code: \(code)"
            
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .serviceUnavailable(let retryAfter):
            if let retryAfter = retryAfter {
                return "Service unavailable. Retry after \(retryAfter) seconds"
            }
            return "Service temporarily unavailable"
        case .gatewayTimeout:
            return "Gateway timeout"
            
        case .unauthorized(let reason):
            return "Unauthorized: \(reason ?? "Invalid authentication")"
        case .forbidden:
            return "Access forbidden"
        case .tokenExpired:
            return "Authentication token has expired"
        case .invalidCredentials:
            return "Invalid credentials provided"
            
        case .sslCertificateError(let error):
            return "SSL certificate error: \(error.localizedDescription)"
        case .insecureConnection:
            return "Connection is not secure"
        case .certificatePinningFailed:
            return "Certificate pinning validation failed"
            
        case .cacheNotFound:
            return "Requested data not found in cache"
        case .cacheExpired:
            return "Cached data has expired"
        case .cacheCorrupted:
            return "Cache data is corrupted"
            
        case .webSocketConnectionFailed(let error):
            return "WebSocket connection failed: \(error.localizedDescription)"
        case .webSocketDisconnected(let code, let reason):
            return "WebSocket disconnected (code: \(code)): \(reason ?? "Unknown reason")"
        case .webSocketInvalidMessage:
            return "Invalid WebSocket message received"
            
        case .graphQLError(let errors):
            let messages = errors.map { $0.message }.joined(separator: ", ")
            return "GraphQL errors: \(messages)"
        case .graphQLValidationFailed(let message):
            return "GraphQL validation failed: \(message)"
            
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .noInternetConnection:
            return "Please check your internet connection and try again"
        case .connectionTimeout:
            return "The server took too long to respond. Please try again"
        case .tooManyRequests:
            return "You're making too many requests. Please wait before trying again"
        case .tokenExpired:
            return "Please log in again to continue"
        case .sslCertificateError, .certificatePinningFailed:
            return "There's a security issue with the connection. Please contact support"
        default:
            return nil
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .noInternetConnection,
             .connectionTimeout,
             .connectionLost,
             .serviceUnavailable,
             .gatewayTimeout,
             .tooManyRequests:
            return true
        default:
            return false
        }
    }
    
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.noInternetConnection, .noInternetConnection),
             (.connectionLost, .connectionLost),
             (.invalidRequest, .invalidRequest),
             (.requestCancelled, .requestCancelled),
             (.invalidResponse, .invalidResponse),
             (.noData, .noData),
             (.forbidden, .forbidden),
             (.tokenExpired, .tokenExpired),
             (.invalidCredentials, .invalidCredentials),
             (.insecureConnection, .insecureConnection),
             (.certificatePinningFailed, .certificatePinningFailed),
             (.cacheNotFound, .cacheNotFound),
             (.cacheExpired, .cacheExpired),
             (.cacheCorrupted, .cacheCorrupted),
             (.webSocketInvalidMessage, .webSocketInvalidMessage),
             (.gatewayTimeout, .gatewayTimeout):
            return true
            
        case (.connectionTimeout(let t1), .connectionTimeout(let t2)):
            return t1 == t2
            
        case (.cannotConnectToHost(let h1), .cannotConnectToHost(let h2)):
            return h1 == h2
            
        case (.invalidURL(let u1), .invalidURL(let u2)):
            return u1 == u2
            
        case (.invalidStatusCode(let c1, let d1), .invalidStatusCode(let c2, let d2)):
            return c1 == c2 && d1 == d2
            
        case (.unauthorized(let r1), .unauthorized(let r2)):
            return r1 == r2
            
        case (.webSocketDisconnected(let c1, let r1), .webSocketDisconnected(let c2, let r2)):
            return c1 == c2 && r1 == r2
            
        case (.graphQLValidationFailed(let m1), .graphQLValidationFailed(let m2)):
            return m1 == m2
            
        default:
            return false
        }
    }
}

/// GraphQL specific error structure
public struct GraphQLError: Error, Codable, Equatable {
    public let message: String
    public let locations: [Location]?
    public let path: [String]?
    public let extensions: [String: String]?
    
    public struct Location: Codable, Equatable {
        public let line: Int
        public let column: Int
    }
    
    public init(message: String, 
                locations: [Location]? = nil,
                path: [String]? = nil,
                extensions: [String: String]? = nil) {
        self.message = message
        self.locations = locations
        self.path = path
        self.extensions = extensions
    }
}