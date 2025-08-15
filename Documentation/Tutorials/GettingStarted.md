# Getting Started with SwiftNetworkPro

Welcome to SwiftNetworkPro! This comprehensive guide will help you integrate enterprise-grade networking into your iOS, macOS, watchOS, and tvOS applications in minutes.

## 🚀 Quick Start Guide

### Step 1: Installation

Choose your preferred installation method:

#### Swift Package Manager (Recommended)

```swift
// In Xcode: File → Add Package Dependencies
// Add: https://github.com/your-username/SwiftNetworkPro
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/SwiftNetworkPro.git", from: "1.0.0")
]
```

#### CocoaPods

```ruby
# Add to your Podfile
pod 'SwiftNetworkPro', '~> 1.0'
```

#### Carthage

```
# Add to your Cartfile
github "your-username/SwiftNetworkPro" ~> 1.0
```

### Step 2: Basic Setup (30 seconds)

Import and configure SwiftNetworkPro in your app:

```swift
import SwiftUI
import SwiftNetworkPro

@main
struct MyApp: App {
    
    init() {
        // Basic configuration
        let config = NetworkConfiguration()
        config.baseURL = "https://api.yourservice.com"
        config.timeoutInterval = 30
        
        NetworkClient.shared.configure(with: config)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Step 3: Your First Network Request

```swift
import SwiftUI
import SwiftNetworkPro

struct ContentView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List(posts) { post in
                VStack(alignment: .leading) {
                    Text(post.title)
                        .font(.headline)
                    Text(post.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Posts")
            .onAppear {
                loadPosts()
            }
        }
    }
    
    private func loadPosts() {
        isLoading = true
        
        Task {
            do {
                // SwiftNetworkPro makes this incredibly simple!
                let posts = try await NetworkClient.shared.get("/posts", as: [Post].self)
                await MainActor.run {
                    self.posts = posts
                    self.isLoading = false
                }
            } catch {
                print("Error loading posts: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct Post: Codable, Identifiable {
    let id: Int
    let title: String
    let body: String
    let userId: Int
}
```

🎉 **Congratulations!** You've successfully integrated SwiftNetworkPro and made your first API call.

## 📚 Interactive Tutorials

### Tutorial 1: Basic GET Requests

**Goal**: Learn how to fetch data from a REST API

**Time**: 5 minutes

**Prerequisites**: Basic Swift knowledge

#### Step-by-Step Instructions

1. **Create a data model**:
```swift
struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let username: String
}
```

2. **Make the API call**:
```swift
func fetchUsers() async throws -> [User] {
    return try await NetworkClient.shared.get("/users", as: [User].self)
}
```

3. **Handle the response in your view**:
```swift
struct UsersView: View {
    @State private var users: [User] = []
    
    var body: some View {
        List(users) { user in
            VStack(alignment: .leading) {
                Text(user.name).font(.headline)
                Text(user.email).font(.caption)
            }
        }
        .task {
            do {
                users = try await fetchUsers()
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
```

**🏆 Success Criteria**: Your app displays a list of users fetched from the API.

### Tutorial 2: POST Requests with Authentication

**Goal**: Learn to send data to an API with authentication

**Time**: 10 minutes

**Prerequisites**: Completed Tutorial 1

#### Step-by-Step Instructions

1. **Configure authentication**:
```swift
let config = NetworkConfiguration()
config.baseURL = "https://api.yourservice.com"
config.defaultHeaders = [
    "Authorization": "Bearer your-api-token",
    "Content-Type": "application/json"
]
NetworkClient.shared.configure(with: config)
```

2. **Create a POST request**:
```swift
struct CreateUserRequest: Codable {
    let name: String
    let email: String
    let username: String
}

func createUser(_ request: CreateUserRequest) async throws -> User {
    return try await NetworkClient.shared.post("/users", 
                                               body: request, 
                                               as: User.self)
}
```

3. **Implement in your UI**:
```swift
struct CreateUserView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var username = ""
    @State private var isCreating = false
    
    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Email", text: $email)
            TextField("Username", text: $username)
            
            Button("Create User") {
                createUserAction()
            }
            .disabled(isCreating || name.isEmpty || email.isEmpty)
        }
    }
    
    private func createUserAction() {
        isCreating = true
        
        Task {
            do {
                let request = CreateUserRequest(
                    name: name,
                    email: email,
                    username: username
                )
                let newUser = try await createUser(request)
                print("Created user: \(newUser)")
                // Handle success (e.g., dismiss view, show success message)
            } catch {
                print("Error creating user: \(error)")
                // Handle error
            }
            
            await MainActor.run {
                isCreating = false
            }
        }
    }
}
```

**🏆 Success Criteria**: Successfully create a new user and receive the response.

### Tutorial 3: Advanced Features - Caching & Retry Logic

**Goal**: Implement intelligent caching and automatic retry mechanisms

**Time**: 15 minutes

**Prerequisites**: Completed Tutorials 1 & 2

#### Step-by-Step Instructions

1. **Configure advanced networking**:
```swift
let config = NetworkConfiguration()
config.baseURL = "https://api.yourservice.com"

// Enable intelligent caching
config.cachePolicy = .returnCacheDataElseLoad
config.cacheSize = 50 * 1024 * 1024 // 50MB cache

// Configure retry logic
config.retryPolicy = .exponentialBackoff(maxRetries: 3)
config.retryDelay = 1.0 // Start with 1 second delay

// Enable compression
config.compressionEnabled = true

NetworkClient.shared.configure(with: config)
```

2. **Implement cached data loading**:
```swift
func loadCachedPosts() async throws -> [Post] {
    // This will return cached data if available, otherwise fetch from network
    return try await NetworkClient.shared.get("/posts", 
                                              as: [Post].self,
                                              cachePolicy: .returnCacheDataElseLoad)
}

func forceRefreshPosts() async throws -> [Post] {
    // This will always fetch fresh data and update the cache
    return try await NetworkClient.shared.get("/posts", 
                                              as: [Post].self,
                                              cachePolicy: .reloadIgnoringCacheData)
}
```

3. **Add retry logic with user feedback**:
```swift
struct PostsView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var retryCount = 0
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack {
                        ProgressView()
                        if retryCount > 0 {
                            Text("Retrying... (\(retryCount)/3)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } else if let error = errorMessage {
                    VStack {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            loadPosts(forceRefresh: true)
                        }
                    }
                } else {
                    List(posts) { post in
                        PostRowView(post: post)
                    }
                    .refreshable {
                        await loadPosts(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("Posts")
            .onAppear {
                loadPosts()
            }
        }
    }
    
    private func loadPosts(forceRefresh: Bool = false) {
        isLoading = true
        errorMessage = nil
        retryCount = 0
        
        Task {
            do {
                // Monitor retry attempts
                NetworkClient.shared.onRetryAttempt { attempt in
                    await MainActor.run {
                        retryCount = attempt
                    }
                }
                
                let posts = forceRefresh ? 
                    try await forceRefreshPosts() : 
                    try await loadCachedPosts()
                
                await MainActor.run {
                    self.posts = posts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
```

**🏆 Success Criteria**: App loads cached data instantly and gracefully handles network failures with automatic retries.

### Tutorial 4: Enterprise Features - AI Optimization & Security

**Goal**: Enable AI-powered optimization and enterprise security

**Time**: 20 minutes

**Prerequisites**: Completed previous tutorials

#### Step-by-Step Instructions

1. **Enable AI optimization**:
```swift
let config = NetworkConfiguration()
config.baseURL = "https://api.yourservice.com"

// Enable AI-powered network intelligence
config.aiOptimizationEnabled = true
config.networkIntelligenceLevel = .adaptive

// The AI will learn from your app's network patterns and optimize automatically
config.learningEnabled = true

NetworkClient.shared.configure(with: config)
```

2. **Configure enterprise security**:
```swift
let securityConfig = SecurityConfiguration()

// Enable zero-trust security
securityConfig.securityLevel = .enterprise
securityConfig.certificatePinning = true
securityConfig.pinningCertificates = ["api-cert.cer"] // Add your certificate

// Enable quantum-resistant cryptography
securityConfig.quantumResistantEnabled = true

// Apply security configuration
config.securityConfiguration = securityConfig
```

3. **Implement performance monitoring**:
```swift
class NetworkMonitor: ObservableObject {
    @Published var metrics: PerformanceMetrics?
    @Published var optimizationGains: [String: Double] = [:]
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        // Get real-time performance metrics
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                let metrics = await NetworkClient.shared.getPerformanceMetrics()
                let gains = await NetworkIntelligence.shared.getOptimizationGains()
                
                await MainActor.run {
                    self.metrics = metrics
                    self.optimizationGains = gains
                }
            }
        }
    }
}

struct PerformanceDashboard: View {
    @StateObject private var monitor = NetworkMonitor()
    
    var body: some View {
        VStack(spacing: 20) {
            if let metrics = monitor.metrics {
                VStack {
                    Text("Performance Metrics")
                        .font(.headline)
                    
                    HStack {
                        MetricCard(title: "Avg Response", 
                                 value: "\(Int(metrics.averageResponseTime))ms")
                        MetricCard(title: "Success Rate", 
                                 value: "\(Int(metrics.successRate * 100))%")
                        MetricCard(title: "Cache Hit", 
                                 value: "\(Int(metrics.cacheHitRate * 100))%")
                    }
                }
                
                VStack {
                    Text("AI Optimization Gains")
                        .font(.headline)
                    
                    ForEach(Array(monitor.optimizationGains.keys), id: \.self) { endpoint in
                        HStack {
                            Text(endpoint)
                            Spacer()
                            Text("+\(Int(monitor.optimizationGains[endpoint] ?? 0))% faster")
                                .foregroundColor(.green)
                        }
                    }
                }
            } else {
                ProgressView("Loading metrics...")
            }
        }
        .padding()
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
```

**🏆 Success Criteria**: App shows real-time performance metrics and demonstrates AI optimization improvements over time.

## 🛠 Common Use Cases

### Use Case 1: E-commerce App

**Scenario**: Building a shopping app with product listings, search, and checkout

```swift
// Product service
class ProductService {
    private let client = NetworkClient.shared
    
    func getProducts(category: String? = nil) async throws -> [Product] {
        var endpoint = "/products"
        if let category = category {
            endpoint += "?category=\(category)"
        }
        return try await client.get(endpoint, as: [Product].self)
    }
    
    func searchProducts(query: String) async throws -> [Product] {
        return try await client.get("/products/search", 
                                    parameters: ["q": query], 
                                    as: [Product].self)
    }
    
    func getProduct(id: Int) async throws -> ProductDetail {
        return try await client.get("/products/\(id)", as: ProductDetail.self)
    }
}

// Usage in SwiftUI
struct ProductListView: View {
    @State private var products: [Product] = []
    @State private var searchText = ""
    private let productService = ProductService()
    
    var body: some View {
        NavigationView {
            List(products) { product in
                ProductRowView(product: product)
            }
            .searchable(text: $searchText)
            .onChange(of: searchText) { newValue in
                searchProducts(query: newValue)
            }
            .task {
                await loadProducts()
            }
        }
    }
    
    private func loadProducts() async {
        do {
            products = try await productService.getProducts()
        } catch {
            print("Error loading products: \(error)")
        }
    }
    
    private func searchProducts(query: String) {
        guard !query.isEmpty else {
            Task { await loadProducts() }
            return
        }
        
        Task {
            do {
                products = try await productService.searchProducts(query: query)
            } catch {
                print("Error searching products: \(error)")
            }
        }
    }
}
```

### Use Case 2: Social Media Feed

**Scenario**: Building a social feed with infinite scroll and real-time updates

```swift
class FeedService {
    private let client = NetworkClient.shared
    
    func getFeed(page: Int = 1, limit: Int = 20) async throws -> FeedResponse {
        return try await client.get("/feed", 
                                    parameters: [
                                        "page": page,
                                        "limit": limit
                                    ], 
                                    as: FeedResponse.self)
    }
    
    func likePost(id: Int) async throws -> LikeResponse {
        return try await client.post("/posts/\(id)/like", as: LikeResponse.self)
    }
    
    func createPost(content: String, images: [Data] = []) async throws -> Post {
        // SwiftNetworkPro handles multipart uploads automatically
        return try await client.uploadMultipart("/posts",
                                                 fields: ["content": content],
                                                 files: images.enumerated().map { (index, data) in
                                                     ("image_\(index)", data, "image.jpg")
                                                 },
                                                 as: Post.self)
    }
}

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    private let feedService = FeedService()
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(posts) { post in
                    PostView(post: post) {
                        // Like action
                        likePost(post)
                    }
                    .onAppear {
                        // Infinite scroll
                        if post == posts.last {
                            loadMorePosts()
                        }
                    }
                }
                
                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .refreshable {
            await refreshFeed()
        }
        .task {
            await loadInitialFeed()
        }
    }
    
    private func loadInitialFeed() async {
        do {
            let response = try await feedService.getFeed(page: 1)
            posts = response.posts
            currentPage = 1
        } catch {
            print("Error loading feed: \(error)")
        }
    }
    
    private func loadMorePosts() {
        guard !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                let response = try await feedService.getFeed(page: currentPage + 1)
                await MainActor.run {
                    posts.append(contentsOf: response.posts)
                    currentPage += 1
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func refreshFeed() async {
        await loadInitialFeed()
    }
    
    private func likePost(_ post: Post) {
        Task {
            do {
                _ = try await feedService.likePost(id: post.id)
                // Update UI to reflect like
            } catch {
                print("Error liking post: \(error)")
            }
        }
    }
}
```

## 🎯 Performance Optimization Tips

### Tip 1: Optimize for Your Use Case

```swift
// For real-time apps (chat, social media)
let realtimeConfig = NetworkConfiguration()
realtimeConfig.timeoutInterval = 10
realtimeConfig.retryPolicy = .exponentialBackoff(maxRetries: 2)
realtimeConfig.cachePolicy = .reloadIgnoringCacheData

// For content apps (news, blogs)
let contentConfig = NetworkConfiguration()
contentConfig.timeoutInterval = 30
contentConfig.cachePolicy = .returnCacheDataElseLoad
contentConfig.cacheSize = 100 * 1024 * 1024 // 100MB

// For enterprise apps
let enterpriseConfig = NetworkConfiguration()
enterpriseConfig.aiOptimizationEnabled = true
enterpriseConfig.networkIntelligenceLevel = .enterprise
enterpriseConfig.securityLevel = .enterprise
```

### Tip 2: Monitor and Optimize

```swift
// Set up performance monitoring
let monitor = PerformanceMonitor.shared
await monitor.setThresholds(
    responseTime: 500,  // 500ms
    errorRate: 0.01,    // 1%
    memoryUsage: 20 * 1024 * 1024  // 20MB
)

await monitor.onThresholdExceeded { metric, value in
    print("⚠️ Performance alert: \(metric) exceeded threshold with \(value)")
    // Take corrective action
}
```

### Tip 3: Leverage AI Optimization

```swift
// Enable AI optimization for automatic improvements
let intelligence = NetworkIntelligence.shared
await intelligence.setOptimizationLevel(.adaptive)

// The AI will automatically:
// - Optimize request timing
// - Improve caching strategies
// - Reduce bandwidth usage
// - Minimize battery impact

// Track improvements
let gains = await intelligence.getOptimizationGains()
print("AI optimization gains: \(gains)")
```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue 1: SSL Certificate Errors

**Problem**: Getting SSL certificate validation errors

**Solution**:
```swift
let config = NetworkConfiguration()
// For development only - disable SSL validation
config.allowInvalidCertificates = true

// For production - use certificate pinning
config.certificatePinning = true
config.pinningCertificates = ["your-cert.cer"]
```

#### Issue 2: Slow Performance

**Problem**: Network requests are slower than expected

**Solution**:
```swift
// Enable AI optimization
config.aiOptimizationEnabled = true

// Use HTTP/3 for better performance
config.httpVersion = .http3

// Enable compression
config.compressionEnabled = true

// Optimize connection pooling
config.connectionPoolSize = 10
```

#### Issue 3: Memory Issues

**Problem**: App using too much memory

**Solution**:
```swift
// Reduce cache size
config.cacheSize = 20 * 1024 * 1024 // 20MB

// Use streaming for large responses
for await chunk in client.stream("/large-data") {
    process(chunk)
}

// Monitor memory usage
if await client.getMemoryUsage() > 50 * 1024 * 1024 {
    await client.optimizeMemoryUsage()
}
```

## 📱 Platform-Specific Features

### iOS Features

```swift
// Background app refresh support
config.backgroundRefreshEnabled = true

// Network reachability
NetworkClient.shared.onNetworkStatusChange { status in
    switch status {
    case .reachable(let connectionType):
        print("Network available: \(connectionType)")
    case .unreachable:
        print("Network unavailable")
    }
}
```

### macOS Features

```swift
// Menu bar integration
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "API Status"

NetworkClient.shared.onRequestComplete { result in
    DispatchQueue.main.async {
        switch result {
        case .success:
            statusItem.button?.title = "✅ API"
        case .failure:
            statusItem.button?.title = "❌ API"
        }
    }
}
```

### watchOS Features

```swift
// Optimize for watch constraints
let watchConfig = NetworkConfiguration()
watchConfig.timeoutInterval = 15  // Shorter timeout
watchConfig.maxConcurrentRequests = 2  // Limit concurrent requests
watchConfig.compressionEnabled = true  // Reduce data usage

// Prioritize essential requests
try await client.get("/essential-data", 
                     priority: .high, 
                     as: EssentialData.self)
```

## 🎓 Next Steps

Congratulations on completing the SwiftNetworkPro tutorials! Here's what you can explore next:

### Advanced Topics
1. **[Enterprise Features](../Enterprise.md)** - Explore advanced security, observability, and AI features
2. **[Performance Optimization](../Performance.md)** - Deep dive into performance tuning
3. **[Custom Interceptors](../Advanced/Interceptors.md)** - Create custom request/response interceptors
4. **[GraphQL Support](../Advanced/GraphQL.md)** - Use SwiftNetworkPro with GraphQL APIs

### Example Projects
- [E-commerce App Example](../Examples/EcommerceApp/)
- [Social Media Feed Example](../Examples/SocialFeed/)
- [Enterprise Dashboard Example](../Examples/EnterpriseDashboard/)

### Community
- [GitHub Discussions](https://github.com/your-username/SwiftNetworkPro/discussions)
- [Stack Overflow Tag](https://stackoverflow.com/questions/tagged/swiftnetworkpro)
- [Discord Community](https://discord.gg/swiftnetworkpro)

## 📊 Quick Reference

### Essential Methods
```swift
// GET request
let data = try await client.get("/endpoint", as: MyModel.self)

// POST request
let response = try await client.post("/endpoint", body: requestData, as: ResponseModel.self)

// PUT request
let updated = try await client.put("/endpoint/\(id)", body: updateData, as: UpdatedModel.self)

// DELETE request
try await client.delete("/endpoint/\(id)")

// Upload file
let result = try await client.upload("/upload", data: fileData, as: UploadResponse.self)

// Download file
let fileData = try await client.download("/file.pdf")

// Stream data
for await chunk in client.stream("/large-dataset") {
    process(chunk)
}
```

### Configuration Quick Setup
```swift
let config = NetworkConfiguration()
config.baseURL = "https://api.example.com"
config.timeoutInterval = 30
config.retryPolicy = .exponentialBackoff(maxRetries: 3)
config.cachePolicy = .returnCacheDataElseLoad
config.aiOptimizationEnabled = true
NetworkClient.shared.configure(with: config)
```

---

## 🤝 Need Help?

- 📖 **Documentation**: [Full API Reference](../API/)
- 💬 **Community**: [GitHub Discussions](https://github.com/your-username/SwiftNetworkPro/discussions)
- 🐛 **Issues**: [Report Bugs](https://github.com/your-username/SwiftNetworkPro/issues)
- 📧 **Contact**: [support@swiftnetworkpro.dev](mailto:support@swiftnetworkpro.dev)

Happy coding with SwiftNetworkPro! 🚀