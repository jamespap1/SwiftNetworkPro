# NetworkClient API Reference

The `NetworkClient` is the core component of SwiftNetworkPro, providing enterprise-grade networking capabilities with AI-powered optimization and zero-trust security.

## Overview

```swift
public class NetworkClient: @unchecked Sendable
```

A comprehensive networking client that combines performance, security, and intelligence in a single, easy-to-use interface.

## Key Features

- 🤖 **AI-Powered Optimization**: Intelligent request optimization and learning
- 🛡️ **Zero-Trust Security**: Multi-factor authentication and threat detection
- 📊 **Real-time Monitoring**: Performance metrics and observability
- 🔐 **Enterprise Security**: Quantum-resistant cryptography and compliance
- ⚡ **High Performance**: HTTP/3, connection pooling, and circuit breakers

## Initialization

### Basic Initialization

```swift
let client = NetworkClient()
```

### Configuration-Based Initialization

```swift
let config = NetworkConfiguration(
    baseURL: "https://api.example.com",
    timeout: 30,
    retryPolicy: .exponentialBackoff(maxAttempts: 3),
    security: .enterprise
)

let client = NetworkClient(configuration: config)
```

### Shared Instance

```swift
let client = NetworkClient.shared
```

## Core Methods

### GET Requests

#### Basic GET

```swift
func get<T: Decodable>(
    _ path: String,
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Parameters:**
- `path`: The API endpoint path
- `type`: The expected response type conforming to `Decodable`
- `headers`: Additional HTTP headers (optional)

**Returns:** Decoded response object of type `T`

**Example:**
```swift
struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

let users = try await client.get("/users", as: [User].self)
```

#### GET with Query Parameters

```swift
func get<T: Decodable>(
    _ path: String,
    queryItems: [URLQueryItem],
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Example:**
```swift
let queryItems = [
    URLQueryItem(name: "page", value: "1"),
    URLQueryItem(name: "limit", value: "10")
]

let paginatedUsers = try await client.get(
    "/users",
    queryItems: queryItems,
    as: PaginatedResponse<User>.self
)
```

### POST Requests

#### POST with JSON Body

```swift
func post<T: Decodable, U: Encodable>(
    _ path: String,
    body: U,
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Parameters:**
- `path`: The API endpoint path
- `body`: The request body conforming to `Encodable`
- `type`: The expected response type conforming to `Decodable`
- `headers`: Additional HTTP headers (optional)

**Example:**
```swift
struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

let request = CreateUserRequest(name: "John Doe", email: "john@example.com")
let createdUser = try await client.post("/users", body: request, as: User.self)
```

#### POST with Form Data

```swift
func post<T: Decodable>(
    _ path: String,
    formData: [String: Any],
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Example:**
```swift
let formData = [
    "name": "John Doe",
    "email": "john@example.com",
    "age": 30
]

let response = try await client.post(
    "/users",
    formData: formData,
    as: CreateUserResponse.self
)
```

### PUT Requests

```swift
func put<T: Decodable, U: Encodable>(
    _ path: String,
    body: U,
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Example:**
```swift
struct UpdateUserRequest: Codable {
    let name: String
    let email: String
}

let updateRequest = UpdateUserRequest(name: "Jane Doe", email: "jane@example.com")
let updatedUser = try await client.put("/users/123", body: updateRequest, as: User.self)
```

### DELETE Requests

```swift
func delete<T: Decodable>(
    _ path: String,
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Example:**
```swift
struct DeleteResponse: Codable {
    let success: Bool
    let message: String
}

let response = try await client.delete("/users/123", as: DeleteResponse.self)
```

### File Operations

#### File Upload

```swift
func upload<T: Decodable>(
    _ fileURL: URL,
    to path: String,
    as type: T.Type,
    headers: [String: String] = [:]
) async throws -> T
```

**Parameters:**
- `fileURL`: Local file URL to upload
- `path`: Upload endpoint path
- `type`: Expected response type
- `headers`: Additional headers (optional)

**Example:**
```swift
struct UploadResponse: Codable {
    let fileId: String
    let url: String
    let size: Int64
}

let fileURL = Bundle.main.url(forResource: "image", withExtension: "jpg")!
let response = try await client.upload(fileURL, to: "/upload", as: UploadResponse.self)
```

#### File Download

```swift
func download(
    from path: String,
    to destinationURL: URL,
    headers: [String: String] = []
) async throws
```

**Example:**
```swift
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let downloadURL = documentsURL.appendingPathComponent("downloaded_file.pdf")

try await client.download(from: "/files/document.pdf", to: downloadURL)
```

## Authentication

### Bearer Token Authentication

```swift
func setAuthentication(_ auth: Authentication) async
```

**Example:**
```swift
await client.setAuthentication(.bearer("your-api-token"))
```

### Basic Authentication

```swift
await client.setAuthentication(.basic(username: "user", password: "pass"))
```

### Custom Authentication

```swift
await client.setAuthentication(.custom { request in
    var modifiedRequest = request
    modifiedRequest.setValue("Custom auth-value", forHTTPHeaderField: "Authorization")
    return modifiedRequest
})
```

## Configuration Management

### Runtime Configuration Updates

```swift
func updateConfiguration(_ config: NetworkConfiguration) async
```

**Example:**
```swift
var newConfig = client.configuration
newConfig.timeout = 60
newConfig.retryPolicy = .linear(maxAttempts: 5)

await client.updateConfiguration(newConfig)
```

### Environment-Specific Configuration

```swift
// Development
let devConfig = NetworkConfiguration(
    baseURL: "https://api-dev.example.com",
    timeout: 60,
    retryPolicy: .none,
    security: .standard
)

// Production
let prodConfig = NetworkConfiguration(
    baseURL: "https://api.example.com",
    timeout: 30,
    retryPolicy: .exponentialBackoff(maxAttempts: 3),
    security: .enterprise
)

await client.updateConfiguration(Environment.current == .development ? devConfig : prodConfig)
```

## Request Interceptors

### Adding Interceptors

```swift
func addInterceptor(_ interceptor: RequestInterceptor)
```

**Example:**
```swift
struct LoggingInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async -> URLRequest {
        print("🚀 Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        return request
    }
}

client.addInterceptor(LoggingInterceptor())
```

### Authentication Interceptor

```swift
struct AuthInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        
        if let token = await TokenManager.shared.getValidToken() {
            modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return modifiedRequest
    }
}

client.addInterceptor(AuthInterceptor())
```

### Retry Interceptor

```swift
struct RetryInterceptor: RequestInterceptor {
    let maxAttempts: Int
    
    func intercept(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.setValue("\(maxAttempts)", forHTTPHeaderField: "X-Max-Retries")
        return modifiedRequest
    }
}

client.addInterceptor(RetryInterceptor(maxAttempts: 3))
```

## Enterprise Features

### AI-Powered Network Intelligence

```swift
// Access network intelligence
let intelligence = client.networkIntelligence

// Set optimization level
await intelligence.setOptimizationLevel(.adaptive)

// Get performance insights
let insights = await intelligence.getPerformanceInsights()
print("Avg response time: \(insights.averageResponseTime)ms")
```

### Zero-Trust Security

```swift
// Access enterprise security
let security = client.enterpriseSecurity

// Enable threat monitoring
await security.enableThreatMonitoring()

// Get security metrics
let metrics = await security.getSecurityMetrics()
print("Security score: \(metrics.overallScore)")
```

### Enterprise Observability

```swift
// Access observability
let observability = client.enterpriseObservability

// Start tracing
let trace = await observability.startTrace(operation: "user_fetch")

// Get health status
let health = await observability.getHealthStatus()
print("System healthy: \(health.isHealthy)")
```

## Performance Monitoring

### Health Status

```swift
func getHealthStatus() async -> HealthStatus
```

**Example:**
```swift
let health = await client.getHealthStatus()

if health.isHealthy {
    print("✅ Network client is healthy")
    print("Response time: \(health.averageResponseTime)ms")
    print("Success rate: \(health.successRate * 100)%")
} else {
    print("⚠️ Network client has issues")
    health.issues.forEach { print("- \($0)") }
}
```

### Performance Metrics

```swift
struct PerformanceMetrics {
    let averageResponseTime: TimeInterval
    let successRate: Double
    let errorRate: Double
    let throughput: Double
    let activeConnections: Int
}

let metrics = await client.getPerformanceMetrics()
```

## Error Handling

### Network Errors

```swift
public enum NetworkError: LocalizedError {
    case invalidURL(String)
    case noData
    case decodingError(Error)
    case encodingError(Error)
    case httpError(Int, Data?)
    case timeout
    case networkUnavailable
    case securityViolation(String)
    case rateLimitExceeded
    case serverError(Int, String?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .noData:
            return "No data received from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .httpError(let code, _):
            return "HTTP error \(code)"
        case .timeout:
            return "Request timeout"
        case .networkUnavailable:
            return "Network unavailable"
        case .securityViolation(let reason):
            return "Security violation: \(reason)"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError(let code, let message):
            return "Server error \(code): \(message ?? "Unknown error")"
        }
    }
}
```

### Error Handling Best Practices

```swift
do {
    let users = try await client.get("/users", as: [User].self)
    // Handle success
} catch NetworkError.timeout {
    // Handle timeout specifically
    print("Request timed out, please try again")
} catch NetworkError.networkUnavailable {
    // Handle network unavailable
    print("Please check your internet connection")
} catch NetworkError.httpError(let code, _) {
    // Handle HTTP errors
    switch code {
    case 401:
        print("Authentication required")
    case 403:
        print("Access forbidden")
    case 404:
        print("Resource not found")
    case 500...599:
        print("Server error, please try again later")
    default:
        print("HTTP error: \(code)")
    }
} catch {
    // Handle other errors
    print("Unexpected error: \(error.localizedDescription)")
}
```

## WebSocket Support

### WebSocket Client

```swift
let wsClient = WebSocketClient(url: URL(string: "wss://api.example.com/ws")!)

// Connect
try await wsClient.connect()

// Listen for messages
wsClient.onMessage { message in
    switch message {
    case .text(let text):
        print("Received text: \(text)")
    case .data(let data):
        print("Received data: \(data.count) bytes")
    }
}

// Send message
try await wsClient.send(text: "Hello, WebSocket!")

// Disconnect
await wsClient.disconnect()
```

## GraphQL Support

### GraphQL Queries

```swift
let query = """
    query GetUser($id: ID!) {
        user(id: $id) {
            id
            name
            email
            posts {
                title
                content
            }
        }
    }
"""

let variables = ["id": "123"]
let result = try await GraphQL.query(query, variables: variables, as: UserResponse.self)
```

### GraphQL Mutations

```swift
let mutation = """
    mutation CreateUser($input: CreateUserInput!) {
        createUser(input: $input) {
            id
            name
            email
        }
    }
"""

let input = ["name": "John Doe", "email": "john@example.com"]
let result = try await GraphQL.mutate(mutation, variables: ["input": input], as: CreateUserResponse.self)
```

## Best Practices

### 1. Configuration Management

```swift
// ✅ Good: Use environment-specific configurations
let config = NetworkConfiguration.production

// ❌ Bad: Hardcode values
let config = NetworkConfiguration(baseURL: "https://hardcoded-url.com")
```

### 2. Error Handling

```swift
// ✅ Good: Handle specific error types
catch NetworkError.rateLimitExceeded {
    await Task.sleep(nanoseconds: 60_000_000_000) // Wait 60 seconds
    // Retry request
}

// ❌ Bad: Generic error handling
catch {
    print("Something went wrong")
}
```

### 3. Request Optimization

```swift
// ✅ Good: Use request batching for multiple requests
async let users = client.get("/users", as: [User].self)
async let posts = client.get("/posts", as: [Post].self)
let (userData, postsData) = try await (users, posts)

// ❌ Bad: Sequential requests
let users = try await client.get("/users", as: [User].self)
let posts = try await client.get("/posts", as: [Post].self)
```

### 4. Security

```swift
// ✅ Good: Use enterprise security for production
let config = NetworkConfiguration(security: .enterprise)

// ✅ Good: Validate SSL certificates
config.certificatePinning = .enabled(certificates: trustedCertificates)

// ❌ Bad: Disable security features
config.certificatePinning = .disabled
```

### 5. Monitoring

```swift
// ✅ Good: Monitor health and performance
let health = await client.getHealthStatus()
if !health.isHealthy {
    // Take corrective action
    await client.resetConnections()
}

// ✅ Good: Use observability features
await client.enterpriseObservability.enableMetricsCollection()
```

## Migration Guide

### From URLSession

```swift
// Old URLSession approach
let url = URL(string: "https://api.example.com/users")!
let (data, _) = try await URLSession.shared.data(from: url)
let users = try JSONDecoder().decode([User].self, from: data)

// New SwiftNetworkPro approach
let users = try await client.get("/users", as: [User].self)
```

### From Alamofire

```swift
// Old Alamofire approach
AF.request("https://api.example.com/users")
    .responseDecodable(of: [User].self) { response in
        switch response.result {
        case .success(let users):
            // Handle success
        case .failure(let error):
            // Handle error
        }
    }

// New SwiftNetworkPro approach
do {
    let users = try await client.get("/users", as: [User].self)
    // Handle success
} catch {
    // Handle error
}
```

## Performance Considerations

### Memory Usage

- NetworkClient uses efficient memory management with automatic cleanup
- Large responses are streamed to prevent memory spikes
- Connection pooling reduces memory overhead for multiple requests

### Battery Life

- Intelligent request batching reduces radio usage
- Background task optimization preserves battery life
- Adaptive timeout adjustments based on network conditions

### Network Efficiency

- HTTP/3 support for optimal performance
- Automatic compression for request/response bodies
- Smart caching reduces redundant network calls

## Thread Safety

NetworkClient is designed to be thread-safe and can be used concurrently from multiple tasks:

```swift
// Safe to call from multiple tasks
Task {
    let users = try await client.get("/users", as: [User].self)
}

Task {
    let posts = try await client.get("/posts", as: [Post].self)
}
```

## Testing

### Unit Testing

```swift
import XCTest
@testable import SwiftNetworkPro

class NetworkClientTests: XCTestCase {
    var client: NetworkClient!
    
    override func setUp() {
        super.setUp()
        let config = NetworkConfiguration(baseURL: "https://test.example.com")
        client = NetworkClient(configuration: config)
    }
    
    func testGetRequest() async throws {
        let users = try await client.get("/users", as: [User].self)
        XCTAssertFalse(users.isEmpty)
    }
}
```

### Mock Client

```swift
class MockNetworkClient: NetworkClient {
    var mockResponses: [String: Any] = [:]
    
    override func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard let mockData = mockResponses[path] as? T else {
            throw NetworkError.noData
        }
        return mockData
    }
}
```

## Debugging

### Enable Debug Logging

```swift
client.configuration.debugLogging = true
```

### Custom Logging

```swift
struct CustomLogger: NetworkLogger {
    func log(_ message: String, level: LogLevel) {
        print("[\(level)] \(message)")
    }
}

client.configuration.logger = CustomLogger()
```

---

## See Also

- [NetworkConfiguration](./NetworkConfiguration.md)
- [Enterprise Features](./Enterprise.md)
- [WebSocket Client](./WebSocketClient.md)
- [GraphQL Support](./GraphQL.md)
- [Error Handling](./ErrorHandling.md)
- [Performance Guide](./Performance.md)
- [Security Guide](./Security.md)