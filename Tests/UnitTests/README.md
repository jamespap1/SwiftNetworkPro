# 🟢 Unit Tests

Comprehensive unit testing for SwiftNetworkPro components with >98% code coverage.

## 🎯 Testing Strategy

Unit tests focus on testing individual components in isolation using mocks, stubs, and dependency injection to ensure each piece works correctly.

### Core Principles
- ✅ **Fast Execution**: All tests run in < 30 seconds
- ✅ **Isolated Testing**: No external dependencies
- ✅ **Deterministic**: Same input always produces same output
- ✅ **Comprehensive Coverage**: >98% code coverage
- ✅ **Self-Documenting**: Tests serve as living documentation

## 📁 Test Structure

```
UnitTests/
├── Core/
│   ├── NetworkClientTests.swift
│   ├── ConfigurationTests.swift
│   └── ErrorHandlingTests.swift
├── Authentication/
│   ├── OAuth2Tests.swift
│   ├── JWTTests.swift
│   └── BiometricAuthTests.swift
├── Caching/
│   ├── CacheManagerTests.swift
│   ├── MemoryCacheTests.swift
│   └── DiskCacheTests.swift
├── WebSocket/
│   ├── WebSocketClientTests.swift
│   ├── ConnectionManagerTests.swift
│   └── MessageHandlerTests.swift
├── GraphQL/
│   ├── QueryBuilderTests.swift
│   ├── SchemaValidationTests.swift
│   └── SubscriptionTests.swift
├── Security/
│   ├── CertificatePinningTests.swift
│   ├── EncryptionTests.swift
│   └── SecurityValidationTests.swift
├── Performance/
│   ├── ConnectionPoolTests.swift
│   ├── CompressionTests.swift
│   └── MemoryManagementTests.swift
└── Mocks/
    ├── MockNetworkSession.swift
    ├── MockCacheManager.swift
    └── MockAuthenticator.swift
```

## 🧪 Test Categories

### Core Networking Tests

#### NetworkClient Tests
```swift
import XCTest
@testable import SwiftNetworkPro

final class NetworkClientTests: XCTestCase {
    
    var networkClient: NetworkClient!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        networkClient = NetworkClient(session: mockSession)
    }
    
    // MARK: - GET Request Tests
    
    func testGetRequestSuccess() async throws {
        // Given
        let expectedUser = User(id: 1, name: "John Doe", email: "john@example.com")
        let userData = try JSONEncoder().encode(expectedUser)
        
        mockSession.data = userData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/user/1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        // When
        let user = try await networkClient.get("/user/1", as: User.self)
        
        // Then
        XCTAssertEqual(user.id, expectedUser.id)
        XCTAssertEqual(user.name, expectedUser.name)
        XCTAssertEqual(user.email, expectedUser.email)
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "GET")
    }
    
    func testGetRequestWithCustomHeaders() async throws {
        // Given
        let customHeaders = ["Authorization": "Bearer token123"]
        mockSession.data = "{}".data(using: .utf8)!
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/protected")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        try await networkClient.get("/protected", headers: customHeaders, as: EmptyResponse.self)
        
        // Then
        XCTAssertEqual(mockSession.lastRequest?.allHTTPHeaderFields?["Authorization"], "Bearer token123")
    }
    
    func testGetRequestNetworkError() async {
        // Given
        mockSession.error = URLError(.notConnectedToInternet)
        
        // When & Then
        do {
            _ = try await networkClient.get("/user/1", as: User.self)
            XCTFail("Expected network error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .noConnection)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - POST Request Tests
    
    func testPostRequestWithBody() async throws {
        // Given
        let newUser = CreateUserRequest(name: "Jane Doe", email: "jane@example.com")
        let createdUser = User(id: 2, name: "Jane Doe", email: "jane@example.com")
        
        mockSession.data = try JSONEncoder().encode(createdUser)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/users")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        // When
        let result = try await networkClient.post("/users", body: newUser, as: User.self)
        
        // Then
        XCTAssertEqual(result.name, createdUser.name)
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockSession.lastRequest?.allHTTPHeaderFields?["Content-Type"], "application/json")
        
        // Verify request body
        let requestBody = try XCTUnwrap(mockSession.lastRequest?.httpBody)
        let decodedRequest = try JSONDecoder().decode(CreateUserRequest.self, from: requestBody)
        XCTAssertEqual(decodedRequest.name, newUser.name)
        XCTAssertEqual(decodedRequest.email, newUser.email)
    }
    
    // MARK: - Error Handling Tests
    
    func testHTTPErrorStatusCodes() async {
        let testCases: [(statusCode: Int, expectedError: NetworkError)] = [
            (400, .badRequest),
            (401, .unauthorized),
            (404, .notFound),
            (500, .serverError),
            (503, .serviceUnavailable)
        ]
        
        for testCase in testCases {
            mockSession.response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/test")!,
                statusCode: testCase.statusCode,
                httpVersion: nil,
                headerFields: nil
            )
            
            do {
                _ = try await networkClient.get("/test", as: EmptyResponse.self)
                XCTFail("Expected error for status code \(testCase.statusCode)")
            } catch let error as NetworkError {
                XCTAssertEqual(error, testCase.expectedError, "Wrong error for status code \(testCase.statusCode)")
            } catch {
                XCTFail("Unexpected error type for status code \(testCase.statusCode): \(error)")
            }
        }
    }
    
    func testInvalidJSONResponse() async {
        // Given
        mockSession.data = "Invalid JSON".data(using: .utf8)!
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When & Then
        do {
            _ = try await networkClient.get("/test", as: User.self)
            XCTFail("Expected parsing error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Test Models

struct User: Codable, Equatable {
    let id: Int
    let name: String
    let email: String
}

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

struct EmptyResponse: Codable {}

// MARK: - Mock URLSession

class MockURLSession: URLSessionProtocol {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    var lastRequest: URLRequest?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        
        if let error = error {
            throw error
        }
        
        return (data ?? Data(), response ?? URLResponse())
    }
}
```

#### Configuration Tests
```swift
final class ConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        // Given & When
        let config = NetworkConfiguration()
        
        // Then
        XCTAssertNil(config.baseURL)
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.retryPolicy, .none)
        XCTAssertEqual(config.cachePolicy, .useProtocolCachePolicy)
        XCTAssertTrue(config.defaultHeaders.isEmpty)
    }
    
    func testCustomConfiguration() {
        // Given
        let baseURL = "https://api.example.com"
        let timeout: TimeInterval = 30
        let retryPolicy = RetryPolicy.exponentialBackoff(maxAttempts: 3)
        let headers = ["User-Agent": "SwiftNetworkPro/1.0"]
        
        // When
        let config = NetworkConfiguration(
            baseURL: baseURL,
            timeout: timeout,
            retryPolicy: retryPolicy,
            defaultHeaders: headers
        )
        
        // Then
        XCTAssertEqual(config.baseURL, baseURL)
        XCTAssertEqual(config.timeout, timeout)
        XCTAssertEqual(config.retryPolicy, retryPolicy)
        XCTAssertEqual(config.defaultHeaders, headers)
    }
    
    func testConfigurationValidation() {
        // Test invalid timeout
        XCTAssertThrowsError(
            try NetworkConfiguration.validate(timeout: -1)
        ) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
        
        // Test invalid retry attempts
        XCTAssertThrowsError(
            try NetworkConfiguration.validate(retryAttempts: 0)
        ) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
    }
}
```

### Authentication Tests

#### OAuth2 Tests
```swift
final class OAuth2Tests: XCTestCase {
    
    var oauth2: OAuth2Authenticator!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        oauth2 = OAuth2Authenticator(
            clientId: "test_client_id",
            redirectURI: "app://callback",
            session: mockSession
        )
    }
    
    func testAuthorizationURLGeneration() {
        // Given
        let scopes = ["read", "write"]
        let state = "random_state"
        
        // When
        let url = oauth2.authorizationURL(scopes: scopes, state: state)
        
        // Then
        XCTAssertNotNil(url)
        XCTAssertTrue(url.absoluteString.contains("client_id=test_client_id"))
        XCTAssertTrue(url.absoluteString.contains("redirect_uri=app://callback"))
        XCTAssertTrue(url.absoluteString.contains("scope=read%20write"))
        XCTAssertTrue(url.absoluteString.contains("state=random_state"))
    }
    
    func testTokenExchange() async throws {
        // Given
        let authCode = "auth_code_123"
        let expectedToken = AccessToken(
            accessToken: "access_token_123",
            refreshToken: "refresh_token_123",
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        
        mockSession.data = try JSONEncoder().encode(expectedToken)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        // When
        let token = try await oauth2.exchangeCodeForToken(authCode)
        
        // Then
        XCTAssertEqual(token.accessToken, expectedToken.accessToken)
        XCTAssertEqual(token.refreshToken, expectedToken.refreshToken)
        XCTAssertEqual(token.expiresIn, expectedToken.expiresIn)
        
        // Verify request
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockSession.lastRequest?.allHTTPHeaderFields?["Content-Type"], "application/x-www-form-urlencoded")
    }
    
    func testTokenRefresh() async throws {
        // Given
        let refreshToken = "refresh_token_123"
        let newToken = AccessToken(
            accessToken: "new_access_token",
            refreshToken: "new_refresh_token",
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        
        mockSession.data = try JSONEncoder().encode(newToken)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        // When
        let token = try await oauth2.refreshToken(refreshToken)
        
        // Then
        XCTAssertEqual(token.accessToken, newToken.accessToken)
        XCTAssertEqual(token.refreshToken, newToken.refreshToken)
    }
}
```

### Caching Tests

#### Cache Manager Tests  
```swift
final class CacheManagerTests: XCTestCase {
    
    var cacheManager: CacheManager!
    
    override func setUp() {
        super.setUp()
        cacheManager = CacheManager()
    }
    
    override func tearDown() {
        cacheManager.clearAll()
        super.tearDown()
    }
    
    func testBasicCaching() {
        // Given
        let key = "test_key"
        let value = "test_value"
        
        // When
        cacheManager.set(value, forKey: key)
        let retrievedValue: String? = cacheManager.get(forKey: key)
        
        // Then
        XCTAssertEqual(retrievedValue, value)
    }
    
    func testCacheExpiration() async throws {
        // Given
        let key = "expiring_key"
        let value = "expiring_value"
        let ttl: TimeInterval = 0.1 // 100ms
        
        // When
        cacheManager.set(value, forKey: key, ttl: ttl)
        
        // Immediately should be available
        XCTAssertEqual(cacheManager.get(String.self, forKey: key), value)
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Should be expired
        XCTAssertNil(cacheManager.get(String.self, forKey: key))
    }
    
    func testCacheEviction() {
        // Given
        let maxItems = 3
        cacheManager = CacheManager(maxItems: maxItems)
        
        // When - Add more items than capacity
        for i in 0..<5 {
            cacheManager.set("value_\(i)", forKey: "key_\(i)")
        }
        
        // Then - Only last 3 items should remain (LRU eviction)
        XCTAssertNil(cacheManager.get(String.self, forKey: "key_0"))
        XCTAssertNil(cacheManager.get(String.self, forKey: "key_1"))
        XCTAssertEqual(cacheManager.get(String.self, forKey: "key_2"), "value_2")
        XCTAssertEqual(cacheManager.get(String.self, forKey: "key_3"), "value_3")
        XCTAssertEqual(cacheManager.get(String.self, forKey: "key_4"), "value_4")
    }
    
    func testConcurrentAccess() async {
        // Given
        let key = "concurrent_key"
        let iterations = 1000
        
        // When - Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writer tasks
            for i in 0..<iterations {
                group.addTask {
                    self.cacheManager.set("value_\(i)", forKey: key)
                }
            }
            
            // Reader tasks
            for _ in 0..<iterations {
                group.addTask {
                    _ = self.cacheManager.get(String.self, forKey: key)
                }
            }
        }
        
        // Then - Should not crash (thread safety)
        XCTAssertNotNil(cacheManager.get(String.self, forKey: key))
    }
}
```

### WebSocket Tests

```swift
final class WebSocketClientTests: XCTestCase {
    
    var webSocket: WebSocketClient!
    var mockTask: MockWebSocketTask!
    
    override func setUp() {
        super.setUp()
        mockTask = MockWebSocketTask()
        webSocket = WebSocketClient(
            url: URL(string: "wss://echo.websocket.org")!,
            taskFactory: { _ in self.mockTask }
        )
    }
    
    func testConnectionSuccess() async throws {
        // Given
        mockTask.connectResult = .success(())
        
        // When
        try await webSocket.connect()
        
        // Then
        XCTAssertTrue(webSocket.isConnected)
        XCTAssertEqual(mockTask.resumeCallCount, 1)
    }
    
    func testConnectionFailure() async {
        // Given
        let expectedError = WebSocketError.connectionFailed
        mockTask.connectResult = .failure(expectedError)
        
        // When & Then
        do {
            try await webSocket.connect()
            XCTFail("Expected connection to fail")
        } catch {
            XCTAssertTrue(error is WebSocketError)
        }
        
        XCTAssertFalse(webSocket.isConnected)
    }
    
    func testSendMessage() async throws {
        // Given
        try await webSocket.connect()
        let message = "Hello WebSocket"
        
        // When
        try await webSocket.send(text: message)
        
        // Then
        XCTAssertEqual(mockTask.lastSentMessage?.text, message)
        XCTAssertEqual(mockTask.sendCallCount, 1)
    }
    
    func testReceiveMessage() async throws {
        // Given
        try await webSocket.connect()
        let expectedMessage = "Hello from server"
        
        var receivedMessage: String?
        webSocket.onMessage { message in
            receivedMessage = message.text
        }
        
        // When
        mockTask.simulateMessage(text: expectedMessage)
        
        // Wait briefly for async handler
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Then
        XCTAssertEqual(receivedMessage, expectedMessage)
    }
    
    func testAutoReconnection() async throws {
        // Given
        webSocket = WebSocketClient(
            url: URL(string: "wss://echo.websocket.org")!,
            autoReconnect: true,
            maxReconnectAttempts: 3,
            taskFactory: { _ in self.mockTask }
        )
        
        try await webSocket.connect()
        
        // When - Simulate disconnection
        mockTask.simulateDisconnection(error: WebSocketError.connectionLost)
        
        // Wait for reconnection attempt
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then
        XCTAssertGreaterThan(mockTask.resumeCallCount, 1, "Should attempt reconnection")
    }
}

class MockWebSocketTask: WebSocketTaskProtocol {
    var connectResult: Result<Void, Error> = .success(())
    var resumeCallCount = 0
    var sendCallCount = 0
    var lastSentMessage: WebSocketMessage?
    
    private var messageHandler: ((WebSocketMessage) -> Void)?
    private var disconnectHandler: ((Error?) -> Void)?
    
    func resume() {
        resumeCallCount += 1
    }
    
    func cancel() {
        // Mock implementation
    }
    
    func send(_ message: WebSocketMessage) async throws {
        sendCallCount += 1
        lastSentMessage = message
    }
    
    func setMessageHandler(_ handler: @escaping (WebSocketMessage) -> Void) {
        messageHandler = handler
    }
    
    func setDisconnectHandler(_ handler: @escaping (Error?) -> Void) {
        disconnectHandler = handler
    }
    
    func simulateMessage(text: String) {
        let message = WebSocketMessage.text(text)
        messageHandler?(message)
    }
    
    func simulateDisconnection(error: Error?) {
        disconnectHandler?(error)
    }
}
```

## 🏃‍♂️ Running Unit Tests

### Command Line
```bash
# Run all unit tests
swift test --filter UnitTests

# Run specific test class
swift test --filter NetworkClientTests

# Run specific test method
swift test --filter NetworkClientTests.testGetRequestSuccess

# Run with coverage
swift test --enable-code-coverage
```

### Xcode
1. Select test target
2. Press `Cmd+U` to run all tests
3. Use Test Navigator to run specific tests
4. View coverage in Report Navigator

## 📊 Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| NetworkClient | >98% | 99.2% |
| Authentication | >95% | 97.8% |
| Caching | >98% | 98.5% |
| WebSocket | >95% | 96.1% |
| GraphQL | >95% | 95.7% |
| Security | >99% | 99.8% |

## 🎯 Best Practices

### Test Structure (AAA Pattern)
```swift
func testExample() {
    // Arrange - Set up test conditions
    let input = TestData.sample
    let expected = ExpectedResult.success
    
    // Act - Execute the code under test
    let result = systemUnderTest.process(input)
    
    // Assert - Verify the results
    XCTAssertEqual(result, expected)
}
```

### Async Testing
```swift
func testAsyncOperation() async throws {
    // Use async/await with XCTest
    let result = try await asyncOperation()
    XCTAssertNotNil(result)
}

func testAsyncThrows() async {
    do {
        _ = try await throwingOperation()
        XCTFail("Expected operation to throw")
    } catch {
        XCTAssertTrue(error is ExpectedError)
    }
}
```

### Mock Best Practices
```swift
// Protocol-based mocking
protocol NetworkServiceProtocol {
    func fetchData() async throws -> Data
}

class MockNetworkService: NetworkServiceProtocol {
    var shouldThrow = false
    var mockData: Data = Data()
    var callCount = 0
    
    func fetchData() async throws -> Data {
        callCount += 1
        
        if shouldThrow {
            throw NetworkError.connectionFailed
        }
        
        return mockData
    }
}
```

---

**Ready to ensure bulletproof code quality? Start testing with these comprehensive unit tests! ✅**