# SwiftNetworkPro Examples

This directory contains comprehensive examples demonstrating how to use SwiftNetworkPro in various scenarios.

## 📁 Examples Overview

### [BasicExample](./BasicExample/)
**Perfect for getting started with SwiftNetworkPro**

- ✅ Simple GET/POST requests
- ✅ Type-safe JSON decoding
- ✅ Error handling patterns
- ✅ Authentication setup
- ✅ File upload/download
- ✅ SwiftUI integration

**Key Features Demonstrated:**
- Modern async/await networking
- Enterprise configuration
- Request interceptors
- Performance monitoring
- AI-powered optimization

## 🚀 Quick Start

### Prerequisites

- **Xcode 15.0+** with Swift 5.9+
- **iOS 15.0+** / macOS 13.0+ / watchOS 9.0+ / tvOS 15.0+ / visionOS 1.0+
- **SwiftNetworkPro 3.0+**

### Installation

1. **Add SwiftNetworkPro to your project**:
   ```swift
   dependencies: [
       .package(url: "https://github.com/muhittincamdali/SwiftNetworkPro", from: "3.0.0")
   ]
   ```

2. **Import and configure**:
   ```swift
   import SwiftNetworkPro
   
   let client = NetworkClient(configuration: .enterprise)
   ```

3. **Start making requests**:
   ```swift
   let users = try await client.get("/users", as: [User].self)
   ```

## 📖 Example Walkthrough

### Basic Networking

```swift
import SwiftNetworkPro

// 1. Configure the client
let config = NetworkConfiguration(
    baseURL: "https://api.example.com",
    timeout: 30,
    retryPolicy: .exponentialBackoff(maxAttempts: 3),
    security: .enterprise
)

let client = NetworkClient(configuration: config)

// 2. Make requests
let users = try await client.get("/users", as: [User].self)
let newUser = try await client.post("/users", body: createRequest, as: User.self)
```

### Advanced Features

```swift
// AI-powered optimization
let optimizedClient = NetworkClient.shared
await optimizedClient.networkIntelligence.setOptimizationLevel(.adaptive)

// Real-time monitoring
let healthStatus = await optimizedClient.getHealthStatus()
print("System health: \(healthStatus.isHealthy)")
```

## 🔧 Configuration Examples

### Development Configuration
```swift
let devConfig = NetworkConfiguration(
    baseURL: "https://api-dev.example.com",
    timeout: 60, // Longer timeout for debugging
    retryPolicy: .none, // No retries for debugging
    cachePolicy: .reloadIgnoringLocalCacheData,
    security: .standard
)
```

### Production Configuration
```swift
let prodConfig = NetworkConfiguration(
    baseURL: "https://api.example.com",
    timeout: 30,
    retryPolicy: .exponentialBackoff(maxAttempts: 3),
    cachePolicy: .returnCacheDataElseLoad,
    security: .enterprise
)
```

## 📚 Additional Resources

- [SwiftNetworkPro Documentation](../README.md)
- [Contributing](../CONTRIBUTING.md)

---

**Ready to build amazing networking features? Start with the [BasicExample](./BasicExample/) and work your way up! 🚀**