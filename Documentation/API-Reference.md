# SwiftNetworkPro API Reference

## Overview

SwiftNetworkPro provides a modern, async/await-based networking framework for iOS, macOS, watchOS, tvOS, and visionOS applications. This comprehensive API reference covers all public interfaces, classes, and protocols.

## Table of Contents

- [NetworkClient](#networkclient)
- [Configuration](#configuration)
- [WebSocket](#websocket)
- [GraphQL](#graphql)
- [HTTP/2](#http2)
- [Security](#security)
- [Cache Management](#cache-management)
- [Traffic Analysis](#traffic-analysis)
- [Error Handling](#error-handling)
- [Protocols](#protocols)

## NetworkClient

The main networking client providing HTTP request capabilities.

### Class Definition

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor NetworkClient
```

### Properties

```swift
/// Shared singleton instance
public static let shared: NetworkClient

/// Current configuration
private var configuration: NetworkConfiguration
```

### Initialization

```swift
/// Initialize with custom configuration
public init(configuration: NetworkConfiguration = .default)
```

### HTTP Methods

#### GET Request

```swift
/// Perform a GET request
/// - Parameters:
///   - endpoint: The API endpoint
///   - parameters: Query parameters (optional)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func get<T: Decodable>(
    _ endpoint: String,
    parameters: [String: Any]? = nil,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

#### POST Request

```swift
/// Perform a POST request
/// - Parameters:
///   - endpoint: The API endpoint
///   - body: Request body (optional)
///   - parameters: Additional parameters (optional)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func post<T: Decodable, B: Encodable>(
    _ endpoint: String,
    body: B? = nil,
    parameters: [String: Any]? = nil,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

#### PUT Request

```swift
/// Perform a PUT request
/// - Parameters:
///   - endpoint: The API endpoint
///   - body: Request body (optional)
///   - parameters: Additional parameters (optional)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func put<T: Decodable, B: Encodable>(
    _ endpoint: String,
    body: B? = nil,
    parameters: [String: Any]? = nil,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

#### PATCH Request

```swift
/// Perform a PATCH request
/// - Parameters:
///   - endpoint: The API endpoint
///   - body: Request body (optional)
///   - parameters: Additional parameters (optional)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func patch<T: Decodable, B: Encodable>(
    _ endpoint: String,
    body: B? = nil,
    parameters: [String: Any]? = nil,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

#### DELETE Request

```swift
/// Perform a DELETE request
/// - Parameters:
///   - endpoint: The API endpoint
///   - parameters: Query parameters (optional)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func delete<T: Decodable>(
    _ endpoint: String,
    parameters: [String: Any]? = nil,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

### File Operations

#### Download File

```swift
/// Download a file from URL
/// - Parameters:
///   - url: Source URL string
///   - destination: Local destination URL
///   - progress: Progress callback (optional)
/// - Returns: Final file URL
/// - Throws: NetworkError on failure
public func download(
    from url: String,
    to destination: URL,
    progress: ((Double) -> Void)? = nil
) async throws -> URL
```

#### Upload File

```swift
/// Upload a file to endpoint
/// - Parameters:
///   - file: Local file URL
///   - endpoint: Upload endpoint
///   - method: HTTP method (default: POST)
///   - headers: Additional headers (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: NetworkError on failure
public func upload<T: Decodable>(
    _ file: URL,
    to endpoint: String,
    method: HTTPMethod = .post,
    headers: [String: String]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

### Request Management

#### Cancel Requests

```swift
/// Cancel all active requests
public func cancelAllRequests()

/// Cancel a specific request by ID
/// - Parameter id: Request identifier
public func cancelRequest(id: UUID)
```

### Configuration Management

```swift
/// Update client configuration
/// - Parameter configuration: New configuration
public func updateConfiguration(_ configuration: NetworkConfiguration)

/// Add request interceptor
/// - Parameter interceptor: Request interceptor
public func addInterceptor(_ interceptor: RequestInterceptor)

/// Add response processor
/// - Parameter processor: Response processor
public func addResponseProcessor(_ processor: ResponseProcessor)
```

## Configuration

### NetworkConfiguration

```swift
public struct NetworkConfiguration {
    public let baseURL: String?
    public let timeout: TimeInterval
    public let retryPolicy: RetryPolicy
    public let cachePolicy: CachePolicy
    public let defaultHeaders: [String: String]
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let enableLogging: Bool
    public let waitsForConnectivity: Bool
    public let allowsCellularAccess: Bool
    public let allowsExpensiveNetworkAccess: Bool
    public let allowsConstrainedNetworkAccess: Bool
    public let urlCache: URLCache?
}
```

#### Default Configuration

```swift
public static let `default` = NetworkConfiguration(
    baseURL: nil,
    timeout: 30,
    retryPolicy: .exponentialBackoff(maxAttempts: 3),
    cachePolicy: .useProtocolCachePolicy,
    defaultHeaders: [
        "Content-Type": "application/json",
        "Accept": "application/json"
    ],
    encoder: JSONEncoder(),
    decoder: JSONDecoder(),
    enableLogging: false,
    waitsForConnectivity: true,
    allowsCellularAccess: true,
    allowsExpensiveNetworkAccess: true,
    allowsConstrainedNetworkAccess: true,
    urlCache: URLCache.shared
)
```

### RetryPolicy

```swift
public enum RetryPolicy {
    case none
    case fixed(maxAttempts: Int, delay: TimeInterval)
    case exponentialBackoff(maxAttempts: Int, baseDelay: TimeInterval = 1.0)
    case custom((Int, Error) -> TimeInterval?)
}
```

### CachePolicy

```swift
public enum CachePolicy {
    case useProtocolCachePolicy
    case reloadIgnoringCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
    case reloadRevalidatingCacheData
}
```

## WebSocket

### WebSocketClient

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor WebSocketClient
```

#### Initialization

```swift
/// Initialize WebSocket client
/// - Parameters:
///   - url: WebSocket URL
///   - protocols: Supported protocols (optional)
///   - configuration: WebSocket configuration (optional)
public init(
    url: URL,
    protocols: [String] = [],
    configuration: WebSocketConfiguration = .default
)
```

#### Connection Management

```swift
/// Connect to WebSocket server
/// - Throws: WebSocketError on failure
public func connect() async throws

/// Disconnect from server
/// - Parameter code: Close code (optional)
/// - Parameter reason: Close reason (optional)
public func disconnect(code: WebSocketCloseCode = .normalClosure, reason: String? = nil) async

/// Check if connected
public var isConnected: Bool { get async }
```

#### Message Handling

```swift
/// Send text message
/// - Parameter text: Message text
/// - Throws: WebSocketError on failure
public func send(text: String) async throws

/// Send binary data
/// - Parameter data: Binary data
/// - Throws: WebSocketError on failure
public func send(data: Data) async throws

/// Set message handler
/// - Parameter handler: Message handler closure
public func onMessage(_ handler: @escaping (WebSocketMessage) -> Void)

/// Set connection state handler
/// - Parameter handler: Connection state handler closure
public func onConnectionState(_ handler: @escaping (WebSocketConnectionState) -> Void)
```

## GraphQL

### GraphQLClient

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor GraphQLClient
```

#### Initialization

```swift
/// Initialize GraphQL client
/// - Parameter configuration: GraphQL configuration
public init(configuration: GraphQLConfiguration)
```

#### Query Operations

```swift
/// Execute GraphQL query
/// - Parameters:
///   - query: GraphQL query string
///   - variables: Query variables (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: GraphQLError on failure
public func query<T: Decodable>(
    _ query: String,
    variables: [String: Any]? = nil,
    as type: T.Type = T.self
) async throws -> T

/// Execute GraphQL mutation
/// - Parameters:
///   - mutation: GraphQL mutation string
///   - variables: Mutation variables (optional)
///   - type: Expected response type
/// - Returns: Decoded response
/// - Throws: GraphQLError on failure
public func mutation<T: Decodable>(
    _ mutation: String,
    variables: [String: Any]? = nil,
    as type: T.Type = T.self
) async throws -> T
```

#### Subscription Operations

```swift
/// Subscribe to GraphQL subscription
/// - Parameters:
///   - subscription: GraphQL subscription string
///   - variables: Subscription variables (optional)
///   - handler: Data handler closure
/// - Returns: Subscription identifier
/// - Throws: GraphQLError on failure
public func subscribe<T: Decodable>(
    _ subscription: String,
    variables: [String: Any]? = nil,
    type: T.Type = T.self,
    handler: @escaping (Result<T, Error>) -> Void
) async throws -> UUID

/// Cancel subscription
/// - Parameter id: Subscription identifier
public func cancelSubscription(_ id: UUID) async
```

## HTTP/2

### HTTP2Client

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor HTTP2Client
```

#### Advanced Features

```swift
/// Enable server push handling
/// - Parameter handler: Server push handler
public func onServerPush(_ handler: @escaping (HTTP2ServerPush) -> Void)

/// Configure stream priorities
/// - Parameters:
///   - streamId: Stream identifier
///   - priority: Stream priority
public func setStreamPriority(_ streamId: UInt32, priority: HTTP2StreamPriority)

/// Get connection statistics
/// - Returns: Connection statistics
public func getConnectionStats() async -> HTTP2ConnectionStats
```

## Security

### SecurityValidator

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class SecurityValidator
```

#### Security Assessment

```swift
/// Perform comprehensive security assessment
/// - Parameter request: URL request to assess
/// - Returns: Security assessment result
public func assessSecurity(for request: URLRequest) async -> SecurityAssessment

/// Analyze TLS configuration
/// - Parameters:
///   - host: Target host
///   - port: Target port
/// - Returns: TLS analysis result
public func analyzeTLSConfiguration(host: String, port: Int = 443) async -> TLSAnalysis

/// Analyze certificate chain
/// - Parameters:
///   - host: Target host
///   - port: Target port
/// - Returns: Certificate analysis result
public func analyzeCertificateChain(host: String, port: Int = 443) async -> CertificateAnalysis
```

### AuthenticationManager

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor AuthenticationManager
```

#### OAuth2 Authentication

```swift
/// Perform OAuth2 authorization code flow
/// - Parameters:
///   - clientId: OAuth2 client ID
///   - redirectUri: Redirect URI
///   - scopes: Requested scopes
/// - Returns: Access token
/// - Throws: AuthenticationError on failure
public func authorizeWithOAuth2(
    clientId: String,
    redirectUri: String,
    scopes: [String]
) async throws -> AccessToken
```

#### JWT Token Management

```swift
/// Validate JWT token
/// - Parameters:
///   - token: JWT token string
///   - publicKey: Verification public key
/// - Returns: Token validity
/// - Throws: AuthenticationError on failure
public func validateJWTToken(_ token: String, publicKey: SecKey) async throws -> Bool

/// Refresh access token
/// - Parameter refreshToken: Refresh token
/// - Returns: New access token
/// - Throws: AuthenticationError on failure
public func refreshAccessToken(_ refreshToken: String) async throws -> AccessToken
```

## Cache Management

### CacheManager

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor CacheManager
```

#### Cache Operations

```swift
/// Store value in cache
/// - Parameters:
///   - value: Value to store
///   - key: Cache key
///   - policy: Cache policy
public func store<T: Codable>(_ value: T, forKey key: String, policy: CachePolicy = .default) async

/// Retrieve value from cache
/// - Parameters:
///   - key: Cache key
///   - type: Expected value type
/// - Returns: Cached value or nil
public func retrieve<T: Codable>(forKey key: String, as type: T.Type) async -> T?

/// Remove value from cache
/// - Parameter key: Cache key
public func remove(forKey key: String) async

/// Clear entire cache
public func clearAll() async
```

## Traffic Analysis

### TrafficAnalyzer

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor TrafficAnalyzer
```

#### Analysis Operations

```swift
/// Start traffic monitoring
public func startMonitoring() async

/// Stop traffic monitoring
public func stopMonitoring() async

/// Get traffic statistics
/// - Returns: Current traffic statistics
public func getStatistics() async -> TrafficStatistics

/// Export analysis data
/// - Parameters:
///   - format: Export format
///   - timeRange: Time range for export
/// - Returns: Exported data
public func exportData(format: ExportFormat, timeRange: TimeRange) async -> Data
```

## Error Handling

### NetworkError

```swift
public enum NetworkError: Error, LocalizedError {
    case invalidURL(String)
    case noData
    case invalidResponse
    case invalidStatusCode(Int, data: Data?)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case unauthorized(reason: String?)
    case forbidden
    case tooManyRequests(retryAfter: Double?)
    case serverError(statusCode: Int, message: String?)
    case networkUnavailable
    case timeout
    case cancelled
    case securityError(String)
    case unknown(Error)
}
```

#### Error Properties

```swift
/// Localized error description
public var errorDescription: String? { get }

/// Recovery suggestion
public var recoverySuggestion: String? { get }

/// Whether error is retryable
public var isRetryable: Bool { get }

/// Associated HTTP status code
public var statusCode: Int? { get }
```

## Protocols

### RequestInterceptor

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public protocol RequestInterceptor: Actor {
    /// Intercept and potentially modify request
    /// - Parameter request: Original request
    /// - Returns: Modified request
    /// - Throws: Error if interception fails
    func intercept(_ request: URLRequest) async throws -> URLRequest
}
```

### ResponseProcessor

```swift
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public protocol ResponseProcessor: Actor {
    /// Process response data
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URL response
    /// - Returns: Processed data
    /// - Throws: Error if processing fails
    func process(_ data: Data, response: URLResponse) async throws -> Data
}
```

### NetworkMonitorProtocol

```swift
public protocol NetworkMonitorProtocol: Actor {
    /// Current network connectivity status
    var isConnected: Bool { get async }
    
    /// Current connection type
    var connectionType: NetworkConnectionType { get async }
    
    /// Start monitoring network changes
    func startMonitoring() async
    
    /// Stop monitoring network changes
    func stopMonitoring() async
    
    /// Set network status change handler
    /// - Parameter handler: Status change handler
    func onStatusChange(_ handler: @escaping (NetworkStatus) -> Void) async
}
```

## Version Information

| Component | Version | Availability |
|-----------|---------|--------------|
| NetworkClient | 2.0.0+ | iOS 15.0+, macOS 13.0+, watchOS 9.0+, tvOS 15.0+, visionOS 1.0+ |
| WebSocketClient | 2.0.0+ | iOS 15.0+, macOS 13.0+, watchOS 9.0+, tvOS 15.0+, visionOS 1.0+ |
| GraphQLClient | 2.0.0+ | iOS 15.0+, macOS 13.0+, watchOS 9.0+, tvOS 15.0+, visionOS 1.0+ |
| HTTP2Client | 1.1.0+ | iOS 15.0+, macOS 13.0+, watchOS 9.0+, tvOS 15.0+, visionOS 1.0+ |
| SecurityValidator | 2.0.0+ | iOS 15.0+, macOS 13.0+, watchOS 9.0+, tvOS 15.0+, visionOS 1.0+ |

## Migration Guides

- [Migrating from v1.x to v2.0](Migration/v1-to-v2.md)
- [Migrating from Alamofire](Migration/alamofire-migration.md)
- [Migrating from URLSession](Migration/urlsession-migration.md)

## See Also

- [Getting Started Guide](../README.md)
- [Examples](../Examples/)
- [Performance Guide](Performance.md)
- [Security Guide](Security.md)