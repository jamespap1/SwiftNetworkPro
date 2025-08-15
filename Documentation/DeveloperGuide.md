# Developer Guide - SwiftNetworkPro Best Practices & Tips

## Overview

This guide provides comprehensive best practices, performance tips, and common patterns for developing with SwiftNetworkPro. Whether you're building a small app or an enterprise-scale system, these guidelines will help you write efficient, maintainable, and robust networking code.

## Architecture Best Practices

### 🏗️ Layered Architecture

#### Repository Pattern
```swift
// Define a clean repository interface
protocol UserRepositoryProtocol {
    func fetchUsers() async throws -> [User]
    func fetchUser(id: String) async throws -> User
    func createUser(_ user: User) async throws -> User
    func updateUser(_ user: User) async throws -> User
    func deleteUser(id: String) async throws
}

// Implement with SwiftNetworkPro
class UserRepository: UserRepositoryProtocol {
    private let networkClient: NetworkClient
    
    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }
    
    func fetchUsers() async throws -> [User] {
        try await networkClient.request(
            endpoint: "/users",
            method: .get,
            responseType: [User].self
        )
    }
    
    func fetchUser(id: String) async throws -> User {
        try await networkClient.request(
            endpoint: "/users/\(id)",
            method: .get,
            responseType: User.self
        )
    }
}
```

#### Service Layer
```swift
// Business logic layer
class UserService {
    private let repository: UserRepositoryProtocol
    private let cache: CacheManager
    
    init(repository: UserRepositoryProtocol, cache: CacheManager = .shared) {
        self.repository = repository
        self.cache = cache
    }
    
    func getActiveUsers() async throws -> [User] {
        // Check cache first
        if let cached = cache.get([User].self, forKey: "active_users"),
           !cache.isExpired(forKey: "active_users") {
            return cached
        }
        
        // Fetch from network
        let users = try await repository.fetchUsers()
        let activeUsers = users.filter { $0.isActive }
        
        // Update cache
        cache.set(activeUsers, forKey: "active_users", ttl: 300)
        
        return activeUsers
    }
}
```

### 🔧 Dependency Injection

#### Using Property Wrappers
```swift
@propertyWrapper
struct Injected<T> {
    private let keyPath: WritableKeyPath<InjectedValues, T>
    
    init(_ keyPath: WritableKeyPath<InjectedValues, T>) {
        self.keyPath = keyPath
    }
    
    var wrappedValue: T {
        get { InjectedValues[keyPath] }
        set { InjectedValues[keyPath] = newValue }
    }
}

// Usage
class MyViewModel {
    @Injected(\.networkClient) var networkClient: NetworkClient
    @Injected(\.userService) var userService: UserService
    
    func loadData() async {
        do {
            let users = try await userService.getActiveUsers()
            // Process users
        } catch {
            // Handle error
        }
    }
}
```

#### Container Pattern
```swift
class DependencyContainer {
    static let shared = DependencyContainer()
    
    lazy var networkClient: NetworkClient = {
        NetworkClient(configuration: .production)
    }()
    
    lazy var userRepository: UserRepositoryProtocol = {
        UserRepository(networkClient: networkClient)
    }()
    
    lazy var userService: UserService = {
        UserService(repository: userRepository)
    }()
}
```

## Performance Optimization

### ⚡ Request Optimization

#### Batch Requests
```swift
// Instead of multiple individual requests
func loadDashboard() async throws {
    let users = try await fetchUsers()
    let posts = try await fetchPosts()
    let notifications = try await fetchNotifications()
}

// Use batch requests
func loadDashboard() async throws {
    async let users = fetchUsers()
    async let posts = fetchPosts()
    async let notifications = fetchNotifications()
    
    let (usersResult, postsResult, notificationsResult) = try await (users, posts, notifications)
}
```

#### Request Deduplication
```swift
class RequestDeduplicator {
    private var pendingRequests: [String: Task<Data, Error>] = [:]
    
    func deduplicated<T: Decodable>(
        key: String,
        request: @escaping () async throws -> T
    ) async throws -> T {
        if let existingTask = pendingRequests[key] {
            let data = try await existingTask.value
            return try JSONDecoder().decode(T.self, from: data)
        }
        
        let task = Task {
            let result = try await request()
            let data = try JSONEncoder().encode(result)
            pendingRequests.removeValue(forKey: key)
            return data
        }
        
        pendingRequests[key] = task
        let data = try await task.value
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

### 💾 Caching Strategies

#### Multi-Level Cache
```swift
class MultiLevelCache {
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskCache: DiskCache
    
    func get<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        // Level 1: Memory
        if let entry = memoryCache.object(forKey: key as NSString),
           !entry.isExpired {
            return entry.value as? T
        }
        
        // Level 2: Disk
        if let diskData = diskCache.get(key),
           let value = try? JSONDecoder().decode(T.self, from: diskData) {
            // Promote to memory cache
            memoryCache.setObject(
                CacheEntry(value: value, expiry: Date().addingTimeInterval(300)),
                forKey: key as NSString
            )
            return value
        }
        
        return nil
    }
}
```

#### Smart Cache Invalidation
```swift
class SmartCacheManager {
    func invalidateRelated(to key: String) {
        // Invalidate related cache entries
        switch key {
        case let key where key.hasPrefix("user_"):
            invalidate(pattern: "user_*")
            invalidate(pattern: "posts_by_user_*")
            invalidate(pattern: "comments_by_user_*")
            
        case let key where key.hasPrefix("post_"):
            invalidate(pattern: "post_*")
            invalidate(pattern: "comments_for_post_*")
            
        default:
            invalidate(key: key)
        }
    }
}
```

## Error Handling Patterns

### 🚨 Comprehensive Error Handling

#### Custom Error Types
```swift
enum AppError: LocalizedError {
    case network(NetworkError)
    case validation(String)
    case business(BusinessError)
    case unexpected(Error)
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .validation(let message):
            return "Validation error: \(message)"
        case .business(let error):
            return error.userMessage
        case .unexpected(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .network(.noConnection):
            return "Please check your internet connection"
        case .network(.timeout):
            return "The request took too long. Please try again"
        case .validation:
            return "Please check your input and try again"
        default:
            return nil
        }
    }
}
```

#### Error Recovery
```swift
class NetworkErrorRecovery {
    func recover(from error: NetworkError) async throws -> RecoveryAction {
        switch error {
        case .unauthorized:
            // Try refreshing token
            try await refreshToken()
            return .retry
            
        case .serverError(let code) where code >= 500:
            // Wait and retry for server errors
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return .retry
            
        case .rateLimited(let retryAfter):
            // Wait for rate limit to reset
            try await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
            return .retry
            
        default:
            return .fail
        }
    }
}
```

### 🔄 Retry Strategies

#### Exponential Backoff
```swift
class ExponentialBackoffRetry {
    func execute<T>(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                attempt += 1
                
                if attempt < maxAttempts {
                    let delay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                    let jitter = Double.random(in: 0...delay * 0.1)
                    try await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NetworkError.unknown
    }
}
```

## Security Best Practices

### 🔐 Secure Communication

#### Certificate Pinning
```swift
class CertificatePinner: URLSessionDelegate {
    private let pinnedCertificates: Set<Data>
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Verify certificate
        if verifyCertificate(serverTrust) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

#### Secure Token Storage
```swift
class SecureTokenManager {
    private let keychain = KeychainWrapper()
    
    func saveToken(_ token: String, type: TokenType) {
        let data = token.data(using: .utf8)!
        keychain.set(data, forKey: type.keychainKey, accessibility: .afterFirstUnlock)
    }
    
    func getToken(type: TokenType) -> String? {
        guard let data = keychain.get(type.keychainKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteToken(type: TokenType) {
        keychain.delete(type.keychainKey)
    }
}
```

## Testing Strategies

### 🧪 Unit Testing

#### Mock Network Client
```swift
class MockNetworkClient: NetworkClientProtocol {
    var mockResponses: [String: Result<Data, Error>] = [:]
    
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        responseType: T.Type
    ) async throws -> T {
        guard let result = mockResponses[endpoint] else {
            throw NetworkError.notFound
        }
        
        switch result {
        case .success(let data):
            return try JSONDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }
}

// Usage in tests
func testUserFetch() async throws {
    let mockClient = MockNetworkClient()
    mockClient.mockResponses["/users"] = .success(usersJSON)
    
    let repository = UserRepository(networkClient: mockClient)
    let users = try await repository.fetchUsers()
    
    XCTAssertEqual(users.count, 3)
}
```

### 🎭 Integration Testing

#### Test Fixtures
```swift
class NetworkTestFixtures {
    static func stubRequest(
        _ url: String,
        withFixture fixture: String,
        statusCode: Int = 200
    ) {
        let stubData = loadFixture(fixture)
        
        stub(condition: isPath(url)) { _ in
            HTTPStubsResponse(
                data: stubData,
                statusCode: Int32(statusCode),
                headers: ["Content-Type": "application/json"]
            )
        }
    }
    
    private static func loadFixture(_ name: String) -> Data {
        let bundle = Bundle(for: NetworkTestFixtures.self)
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}
```

## Common Pitfalls & Solutions

### ❌ Pitfall: Memory Leaks

```swift
// BAD: Strong reference cycle
class ViewModel {
    let networkClient = NetworkClient()
    
    func loadData() {
        networkClient.request("/data") { result in
            self.handleResult(result) // Strong reference to self
        }
    }
}

// GOOD: Weak reference
class ViewModel {
    let networkClient = NetworkClient()
    
    func loadData() {
        networkClient.request("/data") { [weak self] result in
            self?.handleResult(result)
        }
    }
}
```

### ❌ Pitfall: Race Conditions

```swift
// BAD: Race condition with multiple requests
var userData: User?

func loadUser() async {
    userData = try? await fetchUser()
}

// GOOD: Use actors for thread safety
actor UserDataManager {
    private var userData: User?
    
    func loadUser() async throws -> User {
        if let userData = userData {
            return userData
        }
        
        let user = try await fetchUser()
        self.userData = user
        return user
    }
}
```

### ❌ Pitfall: Inefficient Polling

```swift
// BAD: Constant polling
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    Task {
        await checkForUpdates()
    }
}

// GOOD: Adaptive polling with backoff
class AdaptivePoller {
    private var interval: TimeInterval = 1.0
    private let maxInterval: TimeInterval = 60.0
    
    func startPolling() {
        Task {
            while !Task.isCancelled {
                let hasUpdates = await checkForUpdates()
                
                if hasUpdates {
                    interval = 1.0 // Reset to minimum
                } else {
                    interval = min(interval * 1.5, maxInterval) // Backoff
                }
                
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
}
```

## Advanced Techniques

### 🚀 Protocol-Oriented Networking

```swift
protocol NetworkEndpoint {
    associatedtype Response: Decodable
    
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
}

extension NetworkClient {
    func request<E: NetworkEndpoint>(_ endpoint: E) async throws -> E.Response {
        try await request(
            endpoint: endpoint.path,
            method: endpoint.method,
            headers: endpoint.headers,
            body: endpoint.body,
            responseType: E.Response.self
        )
    }
}

// Usage
struct GetUsersEndpoint: NetworkEndpoint {
    typealias Response = [User]
    
    let path = "/users"
    let method = HTTPMethod.get
    let headers: [String: String]? = nil
    let body: Data? = nil
}

let users = try await networkClient.request(GetUsersEndpoint())
```

### 🔄 Reactive Networking

```swift
import Combine

extension NetworkClient {
    func publisher<T: Decodable>(
        endpoint: String,
        responseType: T.Type
    ) -> AnyPublisher<T, Error> {
        Future { promise in
            Task {
                do {
                    let result = try await self.request(
                        endpoint: endpoint,
                        method: .get,
                        responseType: T.self
                    )
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
```

## Debugging Tips

### 🐛 Network Debugging

1. **Enable verbose logging**
```swift
#if DEBUG
NetworkDebugger.shared.configure { config in
    config.logLevel = .verbose
}
#endif
```

2. **Use proxy tools** (Charles, Proxyman)
3. **Implement request/response interceptors**
4. **Add timing measurements**
5. **Use network link conditioner**

### 📊 Performance Monitoring

1. **Track key metrics**
   - Response time
   - Success rate
   - Cache hit rate
   - Data usage

2. **Set up alerts for anomalies**
3. **Use distributed tracing**
4. **Monitor error rates**

## Resources

- [NetworkDebugger.md](NetworkDebugger.md) - Advanced debugging tools
- [CLITools.md](CLITools.md) - Command-line utilities
- [API Reference](NetworkClient.md) - Complete API documentation
- [Examples](../Examples/) - Sample projects
- [GitHub Discussions](https://github.com/SwiftNetworkPro/discussions) - Community support