import Foundation
import os.log

/// Protocol for request interceptors
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public protocol RequestInterceptor: Sendable {
    /// Intercept and modify request before sending
    func intercept(_ request: URLRequest) async throws -> URLRequest
    
    /// Handle request retry
    func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool
    
    /// Handle response
    func handle(response: URLResponse?, data: Data?, error: Error?) async throws
}

/// Default request interceptor implementation
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct DefaultRequestInterceptor: RequestInterceptor {
    public init() {}
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        return request
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Default implementation does nothing
    }
}

/// Interceptor chain manager
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor InterceptorChain {
    
    // MARK: - Properties
    
    private var interceptors: [RequestInterceptor] = []
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Interceptors")
    
    // MARK: - Public Methods
    
    /// Add interceptor to chain
    public func add(_ interceptor: RequestInterceptor) {
        interceptors.append(interceptor)
        logger.debug("Added interceptor: \(String(describing: type(of: interceptor)))")
    }
    
    /// Remove all interceptors
    public func removeAll() {
        interceptors.removeAll()
        logger.debug("Removed all interceptors")
    }
    
    /// Process request through interceptor chain
    public func processRequest(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        
        for interceptor in interceptors {
            modifiedRequest = try await interceptor.intercept(modifiedRequest)
        }
        
        return modifiedRequest
    }
    
    /// Check if request should be retried
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        for interceptor in interceptors {
            if await interceptor.shouldRetry(request: request, error: error, retryCount: retryCount) {
                return true
            }
        }
        return false
    }
    
    /// Handle response through interceptor chain
    public func handleResponse(response: URLResponse?, data: Data?, error: Error?) async throws {
        for interceptor in interceptors {
            try await interceptor.handle(response: response, data: data, error: error)
        }
    }
}

// MARK: - Built-in Interceptors

/// Logging interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct LoggingInterceptor: RequestInterceptor {
    
    public enum LogLevel {
        case none
        case basic
        case headers
        case body
        case verbose
    }
    
    private let logLevel: LogLevel
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "HTTP")
    
    public init(logLevel: LogLevel = .basic) {
        self.logLevel = logLevel
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        guard logLevel != .none else { return request }
        
        // Log request
        logger.info("→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        
        if logLevel == .headers || logLevel == .verbose {
            request.allHTTPHeaderFields?.forEach { key, value in
                logger.debug("  \(key): \(value)")
            }
        }
        
        if logLevel == .body || logLevel == .verbose {
            if let body = request.httpBody {
                if let bodyString = String(data: body, encoding: .utf8) {
                    logger.debug("  Body: \(bodyString)")
                } else {
                    logger.debug("  Body: \(body.count) bytes")
                }
            }
        }
        
        return request
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        guard logLevel != .none else { return }
        
        if let error = error {
            logger.error("← Error: \(error.localizedDescription)")
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("← \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "")")
            
            if logLevel == .headers || logLevel == .verbose {
                httpResponse.allHeaderFields.forEach { key, value in
                    logger.debug("  \(key): \(value)")
                }
            }
            
            if logLevel == .body || logLevel == .verbose {
                if let data = data {
                    if let bodyString = String(data: data, encoding: .utf8) {
                        logger.debug("  Body: \(bodyString)")
                    } else {
                        logger.debug("  Body: \(data.count) bytes")
                    }
                }
            }
        }
    }
}

/// Retry interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct RetryInterceptor: RequestInterceptor {
    
    public struct Configuration {
        public let maxRetries: Int
        public let retryDelay: TimeInterval
        public let exponentialBackoff: Bool
        public let retryableErrors: Set<Int>
        public let retryableURLErrors: Set<URLError.Code>
        
        public init(
            maxRetries: Int = 3,
            retryDelay: TimeInterval = 1.0,
            exponentialBackoff: Bool = true,
            retryableErrors: Set<Int> = [408, 429, 500, 502, 503, 504],
            retryableURLErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .notConnectedToInternet]
        ) {
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
            self.exponentialBackoff = exponentialBackoff
            self.retryableErrors = retryableErrors
            self.retryableURLErrors = retryableURLErrors
        }
        
        public static let `default` = Configuration()
        
        public static let aggressive = Configuration(
            maxRetries: 5,
            retryDelay: 0.5,
            exponentialBackoff: true
        )
        
        public static let conservative = Configuration(
            maxRetries: 2,
            retryDelay: 2.0,
            exponentialBackoff: false
        )
    }
    
    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Retry")
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        return request
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        guard retryCount < configuration.maxRetries else {
            logger.debug("Max retries reached: \(retryCount)")
            return false
        }
        
        // Check if error is retryable
        if let urlError = error as? URLError {
            if configuration.retryableURLErrors.contains(urlError.code) {
                await delay(for: retryCount)
                logger.debug("Retrying due to URLError: \(urlError.code)")
                return true
            }
        }
        
        // Check if status code is retryable
        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidStatusCode(let statusCode, _):
                if configuration.retryableErrors.contains(statusCode) {
                    await delay(for: retryCount)
                    logger.debug("Retrying due to status code: \(statusCode)")
                    return true
                }
            default:
                break
            }
        }
        
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Nothing to handle
    }
    
    private func delay(for retryCount: Int) async {
        let delay: TimeInterval
        if configuration.exponentialBackoff {
            delay = configuration.retryDelay * pow(2.0, Double(retryCount))
        } else {
            delay = configuration.retryDelay
        }
        
        logger.debug("Waiting \(delay) seconds before retry #\(retryCount + 1)")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

/// Authentication interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct AuthenticationInterceptor: RequestInterceptor {
    
    private let authenticationManager: AuthenticationManager
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Auth")
    
    public init(authenticationManager: AuthenticationManager) {
        self.authenticationManager = authenticationManager
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        
        // Add authentication headers
        let authHeaders = try await authenticationManager.getAuthenticationHeaders()
        authHeaders.forEach { key, value in
            modifiedRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        return modifiedRequest
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        // Check if error is authentication related
        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidStatusCode(let statusCode, _):
                if statusCode == 401 && retryCount == 0 {
                    // Try to refresh token
                    do {
                        try await authenticationManager.refreshTokenIfNeeded()
                        logger.debug("Token refreshed, retrying request")
                        return true
                    } catch {
                        logger.error("Failed to refresh token: \(error)")
                        return false
                    }
                }
            default:
                break
            }
        }
        
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Handle authentication challenges if needed
    }
}

/// Headers interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct HeadersInterceptor: RequestInterceptor {
    
    private let headers: [String: String]
    private let overwrite: Bool
    
    public init(headers: [String: String], overwrite: Bool = false) {
        self.headers = headers
        self.overwrite = overwrite
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        
        headers.forEach { key, value in
            if overwrite || modifiedRequest.value(forHTTPHeaderField: key) == nil {
                modifiedRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        return modifiedRequest
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Nothing to handle
    }
}

/// User agent interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct UserAgentInterceptor: RequestInterceptor {
    
    private let userAgent: String
    
    public init(userAgent: String? = nil) {
        if let userAgent = userAgent {
            self.userAgent = userAgent
        } else {
            // Generate default user agent
            let bundle = Bundle.main
            let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SwiftNetworkPro"
            let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            
            #if os(iOS)
            let platform = "iOS"
            #elseif os(macOS)
            let platform = "macOS"
            #elseif os(watchOS)
            let platform = "watchOS"
            #elseif os(tvOS)
            let platform = "tvOS"
            #elseif os(visionOS)
            let platform = "visionOS"
            #else
            let platform = "Unknown"
            #endif
            
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            self.userAgent = "\(appName)/\(appVersion) (build \(buildNumber); \(platform) \(osVersion))"
        }
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return modifiedRequest
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Nothing to handle
    }
}

/// Cookie interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct CookieInterceptor: RequestInterceptor {
    
    private let cookieStorage: HTTPCookieStorage
    
    public init(cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieStorage = cookieStorage
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        
        // Add cookies to request
        if let url = request.url,
           let cookies = cookieStorage.cookies(for: url) {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            cookieHeaders.forEach { key, value in
                modifiedRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        return modifiedRequest
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Store cookies from response
        if let httpResponse = response as? HTTPURLResponse,
           let url = httpResponse.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: httpResponse.allHeaderFields as! [String: String], for: url)
            cookies.forEach { cookieStorage.setCookie($0) }
        }
    }
}

/// Timeout interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct TimeoutInterceptor: RequestInterceptor {
    
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = timeout
        return modifiedRequest
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Nothing to handle
    }
}

/// Rate limiting interceptor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor RateLimitInterceptor: RequestInterceptor {
    
    public struct Configuration {
        public let maxRequests: Int
        public let timeWindow: TimeInterval
        public let retryAfterHeader: String
        
        public init(
            maxRequests: Int = 100,
            timeWindow: TimeInterval = 60,
            retryAfterHeader: String = "Retry-After"
        ) {
            self.maxRequests = maxRequests
            self.timeWindow = timeWindow
            self.retryAfterHeader = retryAfterHeader
        }
    }
    
    private let configuration: Configuration
    private var requestTimestamps: [Date] = []
    private var retryAfter: Date?
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "RateLimit")
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        // Check if we're in retry-after period
        if let retryAfter = retryAfter, Date() < retryAfter {
            let waitTime = retryAfter.timeIntervalSinceNow
            logger.debug("Rate limited, waiting \(waitTime) seconds")
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            self.retryAfter = nil
        }
        
        // Clean old timestamps
        let cutoff = Date().addingTimeInterval(-configuration.timeWindow)
        requestTimestamps.removeAll { $0 < cutoff }
        
        // Check rate limit
        if requestTimestamps.count >= configuration.maxRequests {
            let oldestTimestamp = requestTimestamps.first ?? Date()
            let waitTime = configuration.timeWindow - Date().timeIntervalSince(oldestTimestamp)
            if waitTime > 0 {
                logger.debug("Rate limit reached, waiting \(waitTime) seconds")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        // Record this request
        requestTimestamps.append(Date())
        
        return request
    }
    
    public func shouldRetry(request: URLRequest, error: Error, retryCount: Int) async -> Bool {
        // Check for rate limit error
        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidStatusCode(let statusCode, _):
                if statusCode == 429 {
                    logger.debug("Rate limited (429), will retry after delay")
                    return true
                }
            default:
                break
            }
        }
        
        return false
    }
    
    public func handle(response: URLResponse?, data: Data?, error: Error?) async throws {
        // Check for rate limit headers
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                if let retryAfterValue = httpResponse.value(forHTTPHeaderField: configuration.retryAfterHeader) {
                    if let seconds = Int(retryAfterValue) {
                        retryAfter = Date().addingTimeInterval(TimeInterval(seconds))
                        logger.debug("Server requested retry after \(seconds) seconds")
                    } else if let date = DateFormatter.rfc1123.date(from: retryAfterValue) {
                        retryAfter = date
                        logger.debug("Server requested retry after \(date)")
                    }
                }
            }
        }
    }
}

// MARK: - Date Formatter Extension

private extension DateFormatter {
    static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}