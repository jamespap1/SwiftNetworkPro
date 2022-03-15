import Foundation

// MARK: - Request Interceptor

/// Protocol for intercepting and modifying requests before they are sent
public protocol RequestInterceptor: Sendable {
    /// Intercept and potentially modify a request
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

// MARK: - Response Processor

/// Protocol for processing responses after they are received
public protocol ResponseProcessor: Sendable {
    /// Process response data
    func process(_ data: Data, response: URLResponse) async throws -> Data
}

// MARK: - Network Session

/// Protocol for network session abstraction
public protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
    func upload(for request: URLRequest, from data: Data) async throws -> (Data, URLResponse)
}

// MARK: - Request Builder

/// Protocol for building network requests
public protocol RequestBuilder {
    associatedtype Response: Decodable
    
    var method: HTTPMethod { get }
    var endpoint: String { get }
    var parameters: [String: Any]? { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
}

// MARK: - Response Validator

/// Protocol for validating network responses
public protocol ResponseValidator {
    func validate(_ response: URLResponse, data: Data) throws
}

// MARK: - Cache Strategy

/// Protocol for defining cache strategies
public protocol CacheStrategy {
    /// Determine if a request should be cached
    func shouldCache(request: URLRequest) -> Bool
    
    /// Determine if a cached response is still valid
    func isValid(cachedResponse: CachedURLResponse, for request: URLRequest) -> Bool
    
    /// Calculate cache expiration time
    func expirationTime(for response: URLResponse) -> Date?
}

// MARK: - Network Monitor

/// Protocol for monitoring network conditions
public protocol NetworkMonitor {
    var isConnected: Bool { get }
    var connectionType: ConnectionType { get }
    var isExpensive: Bool { get }
    var isConstrained: Bool { get }
    
    func startMonitoring()
    func stopMonitoring()
}

public enum ConnectionType {
    case unknown
    case none
    case cellular
    case wifi
    case ethernet
    case other
}

// MARK: - Authentication Provider

/// Protocol for providing authentication credentials
public protocol AuthenticationProvider: Sendable {
    /// Provide authentication headers for a request
    func authenticationHeaders() async throws -> [String: String]
    
    /// Refresh authentication if needed
    func refreshIfNeeded() async throws
    
    /// Check if authentication is valid
    func isAuthenticated() async -> Bool
}

// MARK: - Progress Reporter

/// Protocol for reporting progress of network operations
public protocol ProgressReporter {
    /// Report progress (0.0 to 1.0)
    func reportProgress(_ progress: Double)
    
    /// Report completion
    func reportCompletion()
    
    /// Report error
    func reportError(_ error: Error)
}

// MARK: - Metrics Collector

/// Protocol for collecting network metrics
public protocol MetricsCollector {
    /// Record request started
    func recordRequestStarted(_ request: URLRequest)
    
    /// Record request completed
    func recordRequestCompleted(_ request: URLRequest, response: URLResponse?, duration: TimeInterval)
    
    /// Record request failed
    func recordRequestFailed(_ request: URLRequest, error: Error, duration: TimeInterval)
    
    /// Get aggregated metrics
    func getMetrics() -> NetworkMetrics
}

public struct NetworkMetrics {
    public let totalRequests: Int
    public let successfulRequests: Int
    public let failedRequests: Int
    public let averageResponseTime: TimeInterval
    public let totalBytesReceived: Int64
    public let totalBytesSent: Int64
    
    public var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests)
    }
    
    public init(
        totalRequests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        averageResponseTime: TimeInterval = 0,
        totalBytesReceived: Int64 = 0,
        totalBytesSent: Int64 = 0
    ) {
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.averageResponseTime = averageResponseTime
        self.totalBytesReceived = totalBytesReceived
        self.totalBytesSent = totalBytesSent
    }
}

// MARK: - Request Modifier

/// Protocol for modifying requests
public protocol RequestModifier {
    func modify(_ request: inout URLRequest)
}

// MARK: - Response Handler

/// Protocol for handling specific response types
public protocol ResponseHandler {
    associatedtype Output
    
    func handle(data: Data, response: URLResponse) throws -> Output
}

// MARK: - Error Recovery

/// Protocol for recovering from errors
public protocol ErrorRecovery {
    /// Attempt to recover from an error
    func recover(from error: Error, request: URLRequest) async throws -> RecoveryAction
}

public enum RecoveryAction {
    case retry(URLRequest)
    case fail
    case fallback(Data)
}

// MARK: - Request Queue

/// Protocol for managing request queue
public protocol RequestQueue {
    /// Add request to queue
    func enqueue(_ request: URLRequest, priority: RequestPriority) async
    
    /// Get next request from queue
    func dequeue() async -> URLRequest?
    
    /// Cancel all requests in queue
    func cancelAll()
    
    /// Get queue size
    var count: Int { get }
}

// MARK: - Data Transformer

/// Protocol for transforming data
public protocol DataTransformer {
    /// Transform input data to output data
    func transform(_ data: Data) throws -> Data
}

// MARK: - URL Builder

/// Protocol for building URLs
public protocol URLBuilder {
    /// Build URL from components
    func buildURL(
        scheme: String?,
        host: String?,
        port: Int?,
        path: String,
        queryItems: [URLQueryItem]?
    ) throws -> URL
}

// MARK: - Mock Support

/// Protocol for mock responses in testing
public protocol MockProvider {
    /// Provide mock response for a request
    func mockResponse(for request: URLRequest) -> (data: Data?, response: URLResponse?, error: Error?)?
}

// MARK: - Plugin

/// Protocol for network client plugins
public protocol NetworkPlugin {
    /// Called before request is sent
    func willSend(_ request: URLRequest) async throws
    
    /// Called after response is received
    func didReceive(_ response: URLResponse, data: Data) async throws
    
    /// Called when request fails
    func didFail(_ request: URLRequest, error: Error) async
}