# NetworkConfiguration API Reference

The `NetworkConfiguration` struct provides comprehensive configuration options for `NetworkClient`, enabling fine-tuned control over networking behavior, security, and performance.

## Overview

```swift
public struct NetworkConfiguration: Sendable
```

A configuration object that defines how the NetworkClient should behave, including timeouts, retry policies, security settings, and enterprise features.

## Properties

### Basic Configuration

#### Base URL

```swift
public var baseURL: String
```

The base URL for all network requests. All relative paths will be appended to this URL.

**Example:**
```swift
var config = NetworkConfiguration()
config.baseURL = "https://api.example.com/v1"
```

#### Timeout

```swift
public var timeout: TimeInterval
```

The timeout interval for network requests in seconds. Default is 30 seconds.

**Example:**
```swift
config.timeout = 60 // 60 seconds timeout
```

#### HTTP Headers

```swift
public var defaultHeaders: [String: String]
```

Default headers that will be added to all requests.

**Example:**
```swift
config.defaultHeaders = [
    "User-Agent": "MyApp/1.0",
    "Accept": "application/json",
    "Content-Type": "application/json"
]
```

### Retry Configuration

#### Retry Policy

```swift
public enum RetryPolicy: Sendable {
    case none
    case linear(maxAttempts: Int)
    case exponentialBackoff(maxAttempts: Int)
    case custom(RetryStrategy)
}

public var retryPolicy: RetryPolicy
```

Defines how failed requests should be retried.

**Options:**
- `.none`: No retry attempts
- `.linear(maxAttempts: Int)`: Linear retry with fixed delay
- `.exponentialBackoff(maxAttempts: Int)`: Exponential backoff retry
- `.custom(RetryStrategy)`: Custom retry logic

**Examples:**
```swift
// No retries
config.retryPolicy = .none

// Linear retry with 3 attempts
config.retryPolicy = .linear(maxAttempts: 3)

// Exponential backoff with 5 attempts
config.retryPolicy = .exponentialBackoff(maxAttempts: 5)

// Custom retry strategy
config.retryPolicy = .custom(MyCustomRetryStrategy())
```

#### Retry Delay

```swift
public var retryDelay: TimeInterval
```

Base delay between retry attempts in seconds. Default is 1 second.

```swift
config.retryDelay = 2.0 // 2 seconds base delay
```

### Cache Configuration

#### Cache Policy

```swift
public enum CachePolicy: Sendable {
    case useProtocolCachePolicy
    case reloadIgnoringLocalCacheData
    case reloadIgnoringLocalAndRemoteCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
    case reloadRevalidatingCacheData
}

public var cachePolicy: CachePolicy
```

Defines how responses should be cached.

**Example:**
```swift
// For development - always reload
config.cachePolicy = .reloadIgnoringLocalCacheData

// For production - use cache when available
config.cachePolicy = .returnCacheDataElseLoad
```

#### Cache Size

```swift
public var cacheSize: Int
```

Maximum cache size in bytes. Default is 50MB.

```swift
config.cacheSize = 100 * 1024 * 1024 // 100MB
```

### Security Configuration

#### Security Level

```swift
public enum SecurityLevel: Sendable {
    case standard
    case enhanced
    case enterprise
}

public var security: SecurityLevel
```

Defines the security level for requests.

**Levels:**
- `.standard`: Basic HTTPS and certificate validation
- `.enhanced`: Additional security checks and monitoring
- `.enterprise`: Full zero-trust security with threat detection

**Example:**
```swift
config.security = .enterprise
```

#### Certificate Pinning

```swift
public enum CertificatePinning: Sendable {
    case disabled
    case enabled(certificates: [SecCertificate])
    case publicKeyPinning(keys: [SecKey])
}

public var certificatePinning: CertificatePinning
```

Configures SSL certificate pinning for enhanced security.

**Examples:**
```swift
// Disable certificate pinning (not recommended for production)
config.certificatePinning = .disabled

// Pin specific certificates
let certificates = [/* your certificates */]
config.certificatePinning = .enabled(certificates: certificates)

// Pin public keys
let publicKeys = [/* your public keys */]
config.certificatePinning = .publicKeyPinning(keys: publicKeys)
```

#### Encryption

```swift
public enum EncryptionLevel: Sendable {
    case none
    case tls
    case aes256
    case endToEnd
}

public var encryption: EncryptionLevel
```

Defines the encryption level for request/response data.

```swift
config.encryption = .aes256
```

### Performance Configuration

#### Connection Pool Size

```swift
public var connectionPoolSize: Int
```

Maximum number of concurrent connections. Default is 10.

```swift
config.connectionPoolSize = 20
```

#### HTTP Version

```swift
public enum HTTPVersion: Sendable {
    case http1_1
    case http2
    case http3
    case automatic
}

public var httpVersion: HTTPVersion
```

Preferred HTTP version for requests.

```swift
config.httpVersion = .http3 // Use HTTP/3 for best performance
```

#### Compression

```swift
public var compressionEnabled: Bool
```

Enable/disable request and response compression. Default is true.

```swift
config.compressionEnabled = true
```

### Logging Configuration

#### Debug Logging

```swift
public var debugLogging: Bool
```

Enable/disable debug logging. Default is false.

```swift
config.debugLogging = true // Enable for development
```

#### Logger

```swift
public protocol NetworkLogger {
    func log(_ message: String, level: LogLevel)
}

public var logger: NetworkLogger?
```

Custom logger for network events.

**Example:**
```swift
struct ConsoleLogger: NetworkLogger {
    func log(_ message: String, level: LogLevel) {
        print("[\(level)] \(message)")
    }
}

config.logger = ConsoleLogger()
```

#### Log Level

```swift
public enum LogLevel: String, CaseIterable {
    case debug
    case info
    case warning
    case error
}

public var logLevel: LogLevel
```

Minimum log level for messages.

```swift
config.logLevel = .info
```

### Enterprise Features

#### AI Optimization

```swift
public var aiOptimizationEnabled: Bool
```

Enable AI-powered request optimization. Default is false.

```swift
config.aiOptimizationEnabled = true
```

#### Network Intelligence

```swift
public var networkIntelligenceLevel: NetworkIntelligenceLevel
```

Level of network intelligence and learning.

```swift
public enum NetworkIntelligenceLevel: Sendable {
    case disabled
    case basic
    case adaptive
    case enterprise
}

config.networkIntelligenceLevel = .adaptive
```

#### Observability

```swift
public var observabilityEnabled: Bool
```

Enable enterprise observability features. Default is false.

```swift
config.observabilityEnabled = true
```

#### Metrics Collection

```swift
public var metricsCollectionEnabled: Bool
```

Enable performance metrics collection. Default is false.

```swift
config.metricsCollectionEnabled = true
```

### Advanced Configuration

#### Circuit Breaker

```swift
public struct CircuitBreakerConfig: Sendable {
    public var failureThreshold: Int
    public var recoveryTimeout: TimeInterval
    public var halfOpenRequests: Int
}

public var circuitBreaker: CircuitBreakerConfig?
```

Circuit breaker configuration for resilient failure handling.

**Example:**
```swift
config.circuitBreaker = CircuitBreakerConfig(
    failureThreshold: 5,      // Open after 5 failures
    recoveryTimeout: 30,      // Wait 30 seconds before retry
    halfOpenRequests: 3       // Allow 3 requests in half-open state
)
```

#### Rate Limiting

```swift
public struct RateLimitConfig: Sendable {
    public var requestsPerMinute: Int
    public var burstCapacity: Int
}

public var rateLimit: RateLimitConfig?
```

Client-side rate limiting configuration.

**Example:**
```swift
config.rateLimit = RateLimitConfig(
    requestsPerMinute: 60,    // 60 requests per minute
    burstCapacity: 10         // Allow bursts of up to 10 requests
)
```

## Predefined Configurations

### Development Configuration

```swift
public static var development: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.timeout = 60
    config.retryPolicy = .none
    config.cachePolicy = .reloadIgnoringLocalCacheData
    config.debugLogging = true
    config.security = .standard
    config.logLevel = .debug
    return config
}
```

### Production Configuration

```swift
public static var production: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.timeout = 30
    config.retryPolicy = .exponentialBackoff(maxAttempts: 3)
    config.cachePolicy = .returnCacheDataElseLoad
    config.debugLogging = false
    config.security = .enterprise
    config.logLevel = .warning
    config.aiOptimizationEnabled = true
    config.observabilityEnabled = true
    config.metricsCollectionEnabled = true
    return config
}
```

### Enterprise Configuration

```swift
public static var enterprise: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.timeout = 30
    config.retryPolicy = .exponentialBackoff(maxAttempts: 5)
    config.cachePolicy = .returnCacheDataElseLoad
    config.security = .enterprise
    config.encryption = .aes256
    config.httpVersion = .http3
    config.aiOptimizationEnabled = true
    config.networkIntelligenceLevel = .enterprise
    config.observabilityEnabled = true
    config.metricsCollectionEnabled = true
    config.connectionPoolSize = 20
    config.compressionEnabled = true
    
    // Enable circuit breaker
    config.circuitBreaker = CircuitBreakerConfig(
        failureThreshold: 3,
        recoveryTimeout: 60,
        halfOpenRequests: 5
    )
    
    // Enable rate limiting
    config.rateLimit = RateLimitConfig(
        requestsPerMinute: 120,
        burstCapacity: 20
    )
    
    return config
}
```

## Initialization

### Default Configuration

```swift
let config = NetworkConfiguration()
```

### With Base URL

```swift
let config = NetworkConfiguration(baseURL: "https://api.example.com")
```

### Builder Pattern

```swift
let config = NetworkConfiguration()
    .baseURL("https://api.example.com")
    .timeout(60)
    .retryPolicy(.exponentialBackoff(maxAttempts: 3))
    .security(.enterprise)
    .enableAIOptimization()
    .enableObservability()
```

## Configuration Validation

### Validation Rules

The configuration is automatically validated when applied to a NetworkClient:

- `baseURL` must be a valid URL
- `timeout` must be greater than 0
- `retryDelay` must be greater than 0
- `connectionPoolSize` must be between 1 and 100
- `cacheSize` must be greater than 0

### Custom Validation

```swift
extension NetworkConfiguration {
    func validate() throws {
        guard URL(string: baseURL) != nil else {
            throw ConfigurationError.invalidBaseURL
        }
        
        guard timeout > 0 else {
            throw ConfigurationError.invalidTimeout
        }
        
        // Additional validation logic
    }
}
```

## Environment-Specific Configurations

### Using Build Configurations

```swift
#if DEBUG
let config = NetworkConfiguration.development
#else
let config = NetworkConfiguration.production
#endif
```

### Using Environment Variables

```swift
var config = NetworkConfiguration()

if let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] {
    config.baseURL = baseURL
}

if let timeoutString = ProcessInfo.processInfo.environment["API_TIMEOUT"],
   let timeout = TimeInterval(timeoutString) {
    config.timeout = timeout
}
```

### Configuration Profiles

```swift
enum ConfigurationProfile {
    case development
    case staging
    case production
    case testing
    
    var networkConfiguration: NetworkConfiguration {
        switch self {
        case .development:
            return .development
        case .staging:
            var config = NetworkConfiguration.production
            config.baseURL = "https://api-staging.example.com"
            config.debugLogging = true
            return config
        case .production:
            return .production
        case .testing:
            var config = NetworkConfiguration.development
            config.baseURL = "https://api-test.example.com"
            config.timeout = 10
            return config
        }
    }
}

let config = ConfigurationProfile.current.networkConfiguration
```

## Security Best Practices

### Production Security

```swift
var config = NetworkConfiguration.enterprise

// Enable certificate pinning
config.certificatePinning = .enabled(certificates: productionCertificates)

// Use strong encryption
config.encryption = .endToEnd

// Enable all security features
config.security = .enterprise

// Disable debug logging
config.debugLogging = false
config.logLevel = .error
```

### Development Security

```swift
var config = NetworkConfiguration.development

// Allow self-signed certificates for local development
config.certificatePinning = .disabled

// Enable debug logging
config.debugLogging = true
config.logLevel = .debug

// Standard security for development
config.security = .standard
```

## Performance Optimization

### High-Performance Configuration

```swift
var config = NetworkConfiguration()

// Use HTTP/3 for best performance
config.httpVersion = .http3

// Increase connection pool
config.connectionPoolSize = 30

// Enable compression
config.compressionEnabled = true

// Aggressive caching
config.cachePolicy = .returnCacheDataElseLoad
config.cacheSize = 200 * 1024 * 1024 // 200MB

// Enable AI optimization
config.aiOptimizationEnabled = true
config.networkIntelligenceLevel = .enterprise

// Circuit breaker for resilience
config.circuitBreaker = CircuitBreakerConfig(
    failureThreshold: 2,
    recoveryTimeout: 30,
    halfOpenRequests: 3
)
```

### Low-Bandwidth Configuration

```swift
var config = NetworkConfiguration()

// Longer timeout for slow connections
config.timeout = 120

// Aggressive retry policy
config.retryPolicy = .exponentialBackoff(maxAttempts: 5)
config.retryDelay = 3.0

// Smaller connection pool
config.connectionPoolSize = 5

// Enable compression
config.compressionEnabled = true

// Smaller cache for memory-constrained devices
config.cacheSize = 10 * 1024 * 1024 // 10MB
```

## Testing Configurations

### Unit Testing

```swift
static var testing: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.baseURL = "https://test.example.com"
    config.timeout = 5
    config.retryPolicy = .none
    config.cachePolicy = .reloadIgnoringLocalCacheData
    config.debugLogging = true
    config.security = .standard
    return config
}
```

### Integration Testing

```swift
static var integration: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.baseURL = "https://api-integration.example.com"
    config.timeout = 30
    config.retryPolicy = .linear(maxAttempts: 2)
    config.debugLogging = true
    config.observabilityEnabled = true
    return config
}
```

### Mock Configuration

```swift
static var mock: NetworkConfiguration {
    var config = NetworkConfiguration()
    config.baseURL = "https://mock.example.com"
    config.timeout = 1
    config.retryPolicy = .none
    config.cachePolicy = .reloadIgnoringLocalCacheData
    return config
}
```

## Migration Guide

### From URLSessionConfiguration

```swift
// Old URLSessionConfiguration
let sessionConfig = URLSessionConfiguration.default
sessionConfig.timeoutIntervalForRequest = 30
sessionConfig.httpMaximumConnectionsPerHost = 10

// New NetworkConfiguration
var config = NetworkConfiguration()
config.timeout = 30
config.connectionPoolSize = 10
```

### From Alamofire

```swift
// Old Alamofire configuration
let configuration = URLSessionConfiguration.default
let manager = Session(configuration: configuration)

// New SwiftNetworkPro configuration
let config = NetworkConfiguration()
let client = NetworkClient(configuration: config)
```

## Common Patterns

### API Key Authentication

```swift
var config = NetworkConfiguration()
config.defaultHeaders["X-API-Key"] = "your-api-key"
```

### Custom User Agent

```swift
var config = NetworkConfiguration()
config.defaultHeaders["User-Agent"] = "MyApp/1.0.0 iOS/17.0"
```

### CORS Headers

```swift
var config = NetworkConfiguration()
config.defaultHeaders["Access-Control-Allow-Origin"] = "*"
```

### Content Type

```swift
var config = NetworkConfiguration()
config.defaultHeaders["Content-Type"] = "application/json"
config.defaultHeaders["Accept"] = "application/json"
```

## Troubleshooting

### Common Issues

#### Invalid Base URL
```swift
// ❌ Wrong
config.baseURL = "not-a-valid-url"

// ✅ Correct
config.baseURL = "https://api.example.com"
```

#### Timeout Too Short
```swift
// ❌ Too short for slow networks
config.timeout = 1

// ✅ Reasonable timeout
config.timeout = 30
```

#### Missing Security Configuration
```swift
// ❌ Using default security in production
let config = NetworkConfiguration()

// ✅ Enterprise security for production
let config = NetworkConfiguration.enterprise
```

### Debug Configuration

```swift
var config = NetworkConfiguration()
config.debugLogging = true
config.logLevel = .debug

// Custom logger for detailed debugging
config.logger = DetailedNetworkLogger()
```

---

## See Also

- [NetworkClient](./NetworkClient.md)
- [Security Configuration](./Security.md)
- [Performance Tuning](./Performance.md)
- [Enterprise Features](./Enterprise.md)
- [Error Handling](./ErrorHandling.md)