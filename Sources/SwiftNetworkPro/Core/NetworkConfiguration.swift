import Foundation

/// Network configuration for SwiftNetwork Pro
public struct NetworkConfiguration {
    
    // MARK: - Properties
    
    /// Base URL for API requests
    public var baseURL: String?
    
    /// Default timeout interval in seconds
    public var timeout: TimeInterval
    
    /// Default headers to include in every request
    public var defaultHeaders: [String: String]
    
    /// JSON encoder for request bodies
    public var encoder: JSONEncoder
    
    /// JSON decoder for response bodies
    public var decoder: JSONDecoder
    
    /// Cache policy
    public var cachePolicy: CachePolicy
    
    /// URL cache configuration
    public var urlCache: URLCache?
    
    /// Retry policy for failed requests
    public var retryPolicy: RetryPolicy
    
    /// Whether to wait for connectivity
    public var waitsForConnectivity: Bool
    
    /// Whether to allow cellular access
    public var allowsCellularAccess: Bool
    
    /// Whether to allow expensive network access
    public var allowsExpensiveNetworkAccess: Bool
    
    /// Whether to allow constrained network access
    public var allowsConstrainedNetworkAccess: Bool
    
    /// Enable request/response logging
    public var enableLogging: Bool
    
    /// Maximum concurrent requests
    public var maxConcurrentRequests: Int
    
    /// Request priority
    public var requestPriority: RequestPriority
    
    /// Security configuration
    public var security: SecurityConfiguration
    
    /// Metrics collection
    public var enableMetrics: Bool
    
    // MARK: - Initialization
    
    public init(
        baseURL: String? = nil,
        timeout: TimeInterval = 30,
        defaultHeaders: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        cachePolicy: CachePolicy = .reloadIgnoringLocalCacheData,
        urlCache: URLCache? = nil,
        retryPolicy: RetryPolicy = .default,
        waitsForConnectivity: Bool = true,
        allowsCellularAccess: Bool = true,
        allowsExpensiveNetworkAccess: Bool = true,
        allowsConstrainedNetworkAccess: Bool = true,
        enableLogging: Bool = false,
        maxConcurrentRequests: Int = 6,
        requestPriority: RequestPriority = .normal,
        security: SecurityConfiguration = .default,
        enableMetrics: Bool = false
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.encoder = encoder
        self.decoder = decoder
        self.cachePolicy = cachePolicy
        self.urlCache = urlCache
        self.retryPolicy = retryPolicy
        self.waitsForConnectivity = waitsForConnectivity
        self.allowsCellularAccess = allowsCellularAccess
        self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
        self.enableLogging = enableLogging
        self.maxConcurrentRequests = maxConcurrentRequests
        self.requestPriority = requestPriority
        self.security = security
        self.enableMetrics = enableMetrics
        
        // Configure encoder/decoder with sensible defaults
        configureEncoderDecoder()
    }
    
    // MARK: - Default Configurations
    
    /// Default configuration with sensible defaults
    public static let `default` = NetworkConfiguration()
    
    /// Development configuration with logging enabled
    public static let development = NetworkConfiguration(
        enableLogging: true,
        security: .development,
        enableMetrics: true
    )
    
    /// Production configuration with strict security
    public static let production = NetworkConfiguration(
        waitsForConnectivity: true,
        enableLogging: false,
        security: .strict,
        enableMetrics: true
    )
    
    /// Testing configuration for unit tests
    public static let testing = NetworkConfiguration(
        timeout: 5,
        retryPolicy: .none,
        waitsForConnectivity: false,
        enableLogging: true
    )
    
    // MARK: - Private Methods
    
    private mutating func configureEncoderDecoder() {
        // Configure encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        
        // Configure decoder
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
    }
}

// MARK: - Cache Policy

public enum CachePolicy {
    case useProtocolCachePolicy
    case reloadIgnoringLocalCacheData
    case reloadIgnoringLocalAndRemoteCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
    case reloadRevalidatingCacheData
    
    var urlCachePolicy: URLRequest.CachePolicy {
        switch self {
        case .useProtocolCachePolicy:
            return .useProtocolCachePolicy
        case .reloadIgnoringLocalCacheData:
            return .reloadIgnoringLocalCacheData
        case .reloadIgnoringLocalAndRemoteCacheData:
            return .reloadIgnoringLocalAndRemoteCacheData
        case .returnCacheDataElseLoad:
            return .returnCacheDataElseLoad
        case .returnCacheDataDontLoad:
            return .returnCacheDataDontLoad
        case .reloadRevalidatingCacheData:
            return .reloadRevalidatingCacheData
        }
    }
}

// MARK: - Retry Policy

public struct RetryPolicy {
    /// Maximum number of retry attempts
    public let maxAttempts: Int
    
    /// Retry strategy
    public let strategy: RetryStrategy
    
    /// Retry condition
    public let condition: RetryCondition
    
    public init(
        maxAttempts: Int = 3,
        strategy: RetryStrategy = .exponentialBackoff(baseDelay: 1.0, maxDelay: 60.0),
        condition: RetryCondition = .onRetryableError
    ) {
        self.maxAttempts = maxAttempts
        self.strategy = strategy
        self.condition = condition
    }
    
    /// Default retry policy
    public static let `default` = RetryPolicy()
    
    /// No retry policy
    public static let none = RetryPolicy(maxAttempts: 0)
    
    /// Aggressive retry policy
    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        strategy: .exponentialBackoff(baseDelay: 0.5, maxDelay: 30.0)
    )
    
    /// Calculate delay for given attempt
    public func delay(for attempt: Int) -> TimeInterval {
        switch strategy {
        case .immediate:
            return 0
        case .constant(let delay):
            return delay
        case .linear(let delay):
            return Double(attempt) * delay
        case .exponentialBackoff(let baseDelay, let maxDelay):
            let delay = baseDelay * pow(2.0, Double(attempt - 1))
            return min(delay, maxDelay)
        case .custom(let calculator):
            return calculator(attempt)
        }
    }
}

public enum RetryStrategy {
    case immediate
    case constant(delay: TimeInterval)
    case linear(delay: TimeInterval)
    case exponentialBackoff(baseDelay: TimeInterval, maxDelay: TimeInterval)
    case custom((Int) -> TimeInterval)
}

public enum RetryCondition {
    case always
    case never
    case onRetryableError
    case onStatusCodes([Int])
    case custom((Error) -> Bool)
}

// MARK: - Request Priority

public enum RequestPriority: Float {
    case veryLow = 0.25
    case low = 0.5
    case normal = 0.75
    case high = 1.0
    case veryHigh = 1.25
}

// MARK: - Security Configuration

public struct SecurityConfiguration {
    /// SSL pinning configuration
    public var sslPinning: SSLPinning
    
    /// Certificate validation
    public var certificateValidation: CertificateValidation
    
    /// Public key pins
    public var publicKeyPins: [String]
    
    /// Trusted domains
    public var trustedDomains: [String]
    
    /// Enable certificate transparency
    public var enableCertificateTransparency: Bool
    
    public init(
        sslPinning: SSLPinning = .none,
        certificateValidation: CertificateValidation = .default,
        publicKeyPins: [String] = [],
        trustedDomains: [String] = [],
        enableCertificateTransparency: Bool = false
    ) {
        self.sslPinning = sslPinning
        self.certificateValidation = certificateValidation
        self.publicKeyPins = publicKeyPins
        self.trustedDomains = trustedDomains
        self.enableCertificateTransparency = enableCertificateTransparency
    }
    
    /// Default security configuration
    public static let `default` = SecurityConfiguration()
    
    /// Development security configuration (less strict)
    public static let development = SecurityConfiguration(
        certificateValidation: .none
    )
    
    /// Strict security configuration
    public static let strict = SecurityConfiguration(
        sslPinning: .publicKey,
        certificateValidation: .full,
        enableCertificateTransparency: true
    )
}

public enum SSLPinning {
    case none
    case certificate
    case publicKey
}

public enum CertificateValidation {
    case none
    case `default`
    case full
}