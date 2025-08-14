# 🟡 Intermediate Examples

Ready to level up? These intermediate examples demonstrate real-world application patterns using SwiftNetworkPro.

## 🎯 What You'll Master

- 🔐 **Authentication & Authorization** (OAuth2, JWT, Biometric)
- 🔄 **Request/Response Interceptors** for advanced processing
- 💾 **Caching Strategies** and offline support
- 🌐 **WebSocket Real-time** communication
- 📊 **GraphQL Integration** with type safety
- 🏗️ **Application Architecture** patterns
- ⚡ **Performance Optimization** techniques

## 📁 Example Projects

### 1. Social Media App 
**File**: `SocialMediaApp/`
**Platform**: iOS (SwiftUI + Combine)
**Complexity**: ⭐⭐⭐

Real social media app with:
- OAuth2 authentication flow
- Post creation with image upload
- Real-time comments via WebSocket
- Infinite scroll with pagination
- Advanced caching strategies

```swift
// Advanced authentication with auto-refresh
let auth = OAuth2Authenticator(
    clientId: "your_client_id",
    redirectURI: "app://callback"
)
client.setAuthenticator(auth)

// Real-time WebSocket integration
let socket = WebSocketClient(url: "wss://api.social.com/live")
socket.onMessage { message in
    handleRealTimeUpdate(message)
}
```

### 2. E-Commerce Platform
**File**: `ECommerceApp/`
**Platform**: iOS (MVVM + SwiftUI)
**Complexity**: ⭐⭐⭐⭐

Complete shopping experience:
- JWT token management
- Product catalog with filtering
- Shopping cart with persistence
- Payment processing integration
- Order tracking with notifications

### 3. News Reader with Offline Support
**File**: `NewsReader/`
**Platform**: macOS (AppKit)
**Complexity**: ⭐⭐⭐

Professional news application:
- Advanced caching with TTL
- Offline reading capabilities
- Background sync strategies
- Search with debounced requests
- Dark mode support

### 4. Real-time Chat Application
**File**: `ChatApp/`
**Platform**: iOS (SwiftUI + WebSocket)
**Complexity**: ⭐⭐⭐⭐

Full-featured chat app:
- WebSocket message handling
- Typing indicators
- Message status (sent/delivered/read)
- File upload with progress
- Push notification integration

### 5. GraphQL Task Manager
**File**: `GraphQLTasks/`
**Platform**: iOS (SwiftUI)
**Complexity**: ⭐⭐⭐

Modern task management:
- GraphQL queries and mutations
- Subscription-based real-time updates
- Optimistic UI updates
- Complex nested data structures
- Schema validation

### 6. Multi-Environment API Client
**File**: `MultiEnvironmentApp/`
**Platform**: iOS/macOS (Universal)
**Complexity**: ⭐⭐⭐

Enterprise configuration patterns:
- Development/Staging/Production environments
- Feature flag integration
- A/B testing support
- Request/response logging
- Analytics integration

## 🏗️ Architectural Patterns

### MVVM with SwiftNetworkPro
```swift
class UserViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let userService: UserServiceProtocol
    
    init(userService: UserServiceProtocol = UserService()) {
        self.userService = userService
    }
    
    @MainActor
    func loadUsers() async {
        isLoading = true
        error = nil
        
        do {
            users = try await userService.fetchUsers()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

protocol UserServiceProtocol {
    func fetchUsers() async throws -> [User]
}

class UserService: UserServiceProtocol {
    private let client = NetworkClient.shared
    
    func fetchUsers() async throws -> [User] {
        return try await client.get("/users", as: [User].self)
    }
}
```

### Repository Pattern Implementation
```swift
protocol UserRepositoryProtocol {
    func getUsers() async throws -> [User]
    func getUser(id: Int) async throws -> User
    func createUser(_ user: CreateUserRequest) async throws -> User
    func updateUser(_ user: User) async throws -> User
    func deleteUser(id: Int) async throws
}

class UserRepository: UserRepositoryProtocol {
    private let networkClient: NetworkClient
    private let cacheManager: CacheManager
    
    init(networkClient: NetworkClient = .shared, cacheManager: CacheManager = .shared) {
        self.networkClient = networkClient
        self.cacheManager = cacheManager
    }
    
    func getUsers() async throws -> [User] {
        // Check cache first
        if let cachedUsers = cacheManager.get([User].self, forKey: "users") {
            return cachedUsers
        }
        
        // Fetch from network
        let users = try await networkClient.get("/users", as: [User].self)
        
        // Cache the result
        cacheManager.set(users, forKey: "users", ttl: 300) // 5 minutes
        
        return users
    }
    
    func createUser(_ user: CreateUserRequest) async throws -> User {
        let newUser = try await networkClient.post("/users", body: user, as: User.self)
        
        // Invalidate users cache
        cacheManager.remove(forKey: "users")
        
        return newUser
    }
}
```

### Advanced Authentication Flow
```swift
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private let client = NetworkClient.shared
    private let tokenStorage = SecureTokenStorage()
    
    func login(email: String, password: String) async throws {
        let request = LoginRequest(email: email, password: password)
        let response = try await client.post("/auth/login", body: request, as: LoginResponse.self)
        
        // Store tokens securely
        try tokenStorage.store(accessToken: response.accessToken)
        try tokenStorage.store(refreshToken: response.refreshToken)
        
        // Configure client for authenticated requests
        await configureAuthenticatedClient(accessToken: response.accessToken)
        
        // Update authentication state
        await MainActor.run {
            self.isAuthenticated = true
            self.currentUser = response.user
        }
    }
    
    private func configureAuthenticatedClient(accessToken: String) async {
        // Add authentication interceptor
        let authInterceptor = AuthenticationInterceptor(token: accessToken)
        client.addInterceptor(authInterceptor)
        
        // Add token refresh interceptor
        let refreshInterceptor = TokenRefreshInterceptor(
            refreshToken: tokenStorage.refreshToken,
            onTokenRefresh: { [weak self] newTokens in
                try? self?.tokenStorage.store(accessToken: newTokens.accessToken)
                try? self?.tokenStorage.store(refreshToken: newTokens.refreshToken)
            }
        )
        client.addInterceptor(refreshInterceptor)
    }
}

class AuthenticationInterceptor: RequestInterceptor {
    private let token: String
    
    init(token: String) {
        self.token = token
    }
    
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return modifiedRequest
    }
}
```

### WebSocket Real-time Implementation
```swift
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isTyping: [String: Bool] = [:]
    
    private let webSocket: WebSocketClient
    private let chatService: ChatService
    
    enum ConnectionStatus {
        case connecting
        case connected
        case disconnected
        case error(String)
    }
    
    init() {
        self.webSocket = WebSocketClient(url: URL(string: "wss://chat.example.com/ws")!)
        self.chatService = ChatService()
        
        setupWebSocketHandlers()
    }
    
    private func setupWebSocketHandlers() {
        webSocket.onConnect { [weak self] in
            await MainActor.run {
                self?.connectionStatus = .connected
            }
        }
        
        webSocket.onMessage { [weak self] message in
            await self?.handleWebSocketMessage(message)
        }
        
        webSocket.onDisconnect { [weak self] error in
            await MainActor.run {
                self?.connectionStatus = error != nil ? .error(error!.localizedDescription) : .disconnected
            }
        }
    }
    
    func connect() async {
        connectionStatus = .connecting
        
        do {
            try await webSocket.connect()
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }
    
    func sendMessage(_ text: String) async {
        let message = ChatMessage(
            id: UUID().uuidString,
            text: text,
            userId: currentUser.id,
            timestamp: Date()
        )
        
        do {
            // Send via WebSocket
            try await webSocket.send(message)
            
            // Also send via REST API for persistence
            try await chatService.sendMessage(message)
        } catch {
            print("Failed to send message: \(error)")
        }
    }
    
    private func handleWebSocketMessage(_ data: Data) async {
        do {
            let message = try JSONDecoder().decode(ChatMessage.self, from: data)
            
            await MainActor.run {
                self.messages.append(message)
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }
}
```

## 🔧 Advanced Configuration Examples

### Custom Caching Strategy
```swift
class SmartCacheManager {
    private let memoryCache = NSCache<NSString, AnyObject>()
    private let diskCache = DiskCache()
    
    func get<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        // Try memory cache first (fastest)
        if let cached = memoryCache.object(forKey: key as NSString) as? T {
            return cached
        }
        
        // Try disk cache (slower but persistent)
        if let cached = await diskCache.get(type, forKey: key) {
            // Store in memory cache for next time
            memoryCache.setObject(cached as AnyObject, forKey: key as NSString)
            return cached
        }
        
        return nil
    }
    
    func set<T: Codable>(_ value: T, forKey key: String, ttl: TimeInterval = 300) async {
        // Store in both caches
        memoryCache.setObject(value as AnyObject, forKey: key as NSString)
        await diskCache.set(value, forKey: key, ttl: ttl)
    }
}
```

### Request/Response Logging
```swift
class NetworkLogger: RequestInterceptor, ResponseProcessor {
    
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        print("🚀 REQUEST")
        print("   URL: \(request.url?.absoluteString ?? "N/A")")
        print("   Method: \(request.httpMethod ?? "GET")")
        print("   Headers: \(request.allHTTPHeaderFields ?? [:])")
        
        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            print("   Body: \(bodyString)")
        }
        
        return request
    }
    
    func process(_ data: Data, response: URLResponse) async throws -> Data {
        if let httpResponse = response as? HTTPURLResponse {
            print("📥 RESPONSE")
            print("   Status: \(httpResponse.statusCode)")
            print("   Headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Body: \(responseString)")
            }
        }
        
        return data
    }
}
```

## 🏃‍♂️ Getting Started

### 1. Choose Your Path
Pick an example that matches your current project needs or learning goals.

### 2. Study the Architecture
Each example includes detailed architectural documentation and patterns.

### 3. Run and Experiment
```bash
cd Examples/Intermediate/SocialMediaApp
open SocialMediaApp.xcodeproj
```

### 4. Customize and Learn
Modify the examples to understand how different patterns work in practice.

## 🎯 Practice Challenges

### Challenge 1: Authentication Flow
Implement a complete authentication system with:
- Login/logout functionality
- Automatic token refresh
- Biometric authentication option
- Session persistence

### Challenge 2: Real-time Dashboard
Create a dashboard that:
- Shows live data updates via WebSocket
- Implements multiple chart types
- Handles connection failures gracefully
- Optimizes for performance

### Challenge 3: Offline-First App
Build an app that:
- Works completely offline
- Syncs data when online
- Handles conflict resolution
- Provides sync status to users

## 🔗 Advanced Resources

- **Authentication Best Practices**: [OAuth 2.0 Security Guide](https://oauth.net/2/security-best-current-practice/)
- **WebSocket Protocol**: [RFC 6455](https://tools.ietf.org/html/rfc6455)
- **GraphQL Best Practices**: [GraphQL Foundation](https://graphql.org/learn/best-practices/)
- **iOS App Architecture**: [Advanced iOS App Architecture](https://store.raywenderlich.com/products/advanced-ios-app-architecture)

## ➡️ Next Level

Ready for enterprise-grade implementations? Continue to:
- **[Advanced Examples](../Advanced/)** - Production-ready architectures

---

**🚀 Build production-ready apps with confidence! Start exploring these intermediate patterns today.**