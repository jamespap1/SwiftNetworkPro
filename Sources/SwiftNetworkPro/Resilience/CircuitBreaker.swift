import Foundation
import os.log

/// Circuit breaker pattern implementation for fault tolerance
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor CircuitBreaker {
    
    // MARK: - Types
    
    /// Circuit breaker state
    public enum State {
        case closed
        case open(until: Date)
        case halfOpen
        
        public var isRequestAllowed: Bool {
            switch self {
            case .closed, .halfOpen:
                return true
            case .open(let until):
                return Date() >= until
            }
        }
        
        public var description: String {
            switch self {
            case .closed:
                return "Closed"
            case .open(let until):
                let remaining = until.timeIntervalSinceNow
                return "Open (resets in \(Int(remaining))s)"
            case .halfOpen:
                return "Half-Open"
            }
        }
    }
    
    /// Circuit breaker configuration
    public struct Configuration {
        public let failureThreshold: Int
        public let successThreshold: Int
        public let timeout: TimeInterval
        public let resetTimeout: TimeInterval
        public let halfOpenMaxAttempts: Int
        public let exponentialBackoff: Bool
        public let maxResetTimeout: TimeInterval
        
        public init(
            failureThreshold: Int = 5,
            successThreshold: Int = 2,
            timeout: TimeInterval = 10,
            resetTimeout: TimeInterval = 60,
            halfOpenMaxAttempts: Int = 3,
            exponentialBackoff: Bool = true,
            maxResetTimeout: TimeInterval = 300
        ) {
            self.failureThreshold = failureThreshold
            self.successThreshold = successThreshold
            self.timeout = timeout
            self.resetTimeout = resetTimeout
            self.halfOpenMaxAttempts = halfOpenMaxAttempts
            self.exponentialBackoff = exponentialBackoff
            self.maxResetTimeout = maxResetTimeout
        }
        
        public static let `default` = Configuration()
        
        public static let aggressive = Configuration(
            failureThreshold: 3,
            successThreshold: 1,
            timeout: 5,
            resetTimeout: 30
        )
        
        public static let conservative = Configuration(
            failureThreshold: 10,
            successThreshold: 5,
            timeout: 15,
            resetTimeout: 120
        )
    }
    
    /// Circuit breaker statistics
    public struct Statistics {
        public let state: State
        public let totalRequests: Int
        public let successfulRequests: Int
        public let failedRequests: Int
        public let rejectedRequests: Int
        public let lastFailureTime: Date?
        public let lastSuccessTime: Date?
        public let consecutiveFailures: Int
        public let consecutiveSuccesses: Int
        public let stateChanges: Int
        public let averageResponseTime: TimeInterval
        
        public var successRate: Double {
            let total = successfulRequests + failedRequests
            return total > 0 ? Double(successfulRequests) / Double(total) : 0
        }
        
        public var failureRate: Double {
            let total = successfulRequests + failedRequests
            return total > 0 ? Double(failedRequests) / Double(total) : 0
        }
    }
    
    /// Circuit breaker error
    public enum CircuitBreakerError: LocalizedError {
        case circuitOpen
        case requestTimeout
        case tooManyRequests
        
        public var errorDescription: String? {
            switch self {
            case .circuitOpen:
                return "Circuit breaker is open - service unavailable"
            case .requestTimeout:
                return "Request timed out"
            case .tooManyRequests:
                return "Too many requests in half-open state"
            }
        }
    }
    
    // MARK: - Properties
    
    private let name: String
    private let configuration: Configuration
    private var state: State = .closed
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "CircuitBreaker")
    
    // Statistics
    private var totalRequests = 0
    private var successfulRequests = 0
    private var failedRequests = 0
    private var rejectedRequests = 0
    private var lastFailureTime: Date?
    private var lastSuccessTime: Date?
    private var consecutiveFailures = 0
    private var consecutiveSuccesses = 0
    private var stateChanges = 0
    private var responseTimes: [TimeInterval] = []
    private var halfOpenAttempts = 0
    private var currentBackoffMultiplier = 1
    
    // Callbacks
    private var stateChangeHandler: ((State, State) -> Void)?
    private var requestHandler: ((Statistics) -> Void)?
    
    // MARK: - Initialization
    
    public init(name: String, configuration: Configuration = .default) {
        self.name = name
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// Execute request through circuit breaker
    public func execute<T>(
        timeout: TimeInterval? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        // Check if request is allowed
        guard await canExecute() else {
            rejectedRequests += 1
            logger.warning("[\(name)] Request rejected - circuit open")
            throw CircuitBreakerError.circuitOpen
        }
        
        totalRequests += 1
        let startTime = Date()
        
        do {
            // Execute with timeout
            let result = try await withTimeout(timeout ?? configuration.timeout) {
                try await operation()
            }
            
            // Record success
            let duration = Date().timeIntervalSince(startTime)
            await recordSuccess(duration: duration)
            
            return result
            
        } catch {
            // Record failure
            let duration = Date().timeIntervalSince(startTime)
            await recordFailure(error: error, duration: duration)
            
            throw error
        }
    }
    
    /// Get current state
    public func getState() -> State {
        // Check if we should transition from open to half-open
        if case .open(let until) = state, Date() >= until {
            transitionTo(.halfOpen)
        }
        return state
    }
    
    /// Get statistics
    public func getStatistics() -> Statistics {
        let averageResponseTime = responseTimes.isEmpty ? 0 : 
            responseTimes.reduce(0, +) / Double(responseTimes.count)
        
        return Statistics(
            state: getState(),
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            failedRequests: failedRequests,
            rejectedRequests: rejectedRequests,
            lastFailureTime: lastFailureTime,
            lastSuccessTime: lastSuccessTime,
            consecutiveFailures: consecutiveFailures,
            consecutiveSuccesses: consecutiveSuccesses,
            stateChanges: stateChanges,
            averageResponseTime: averageResponseTime
        )
    }
    
    /// Reset circuit breaker
    public func reset() {
        logger.info("[\(name)] Manual reset")
        transitionTo(.closed)
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        halfOpenAttempts = 0
        currentBackoffMultiplier = 1
        responseTimes.removeAll()
    }
    
    /// Force open circuit
    public func forceOpen(duration: TimeInterval? = nil) {
        let resetTime = Date().addingTimeInterval(duration ?? configuration.resetTimeout)
        logger.info("[\(name)] Forced open until \(resetTime)")
        transitionTo(.open(until: resetTime))
    }
    
    /// Set state change handler
    public func onStateChange(_ handler: @escaping (State, State) -> Void) {
        self.stateChangeHandler = handler
    }
    
    /// Set request handler
    public func onRequest(_ handler: @escaping (Statistics) -> Void) {
        self.requestHandler = handler
    }
    
    // MARK: - Private Methods
    
    private func canExecute() async -> Bool {
        switch state {
        case .closed:
            return true
            
        case .open(let until):
            if Date() >= until {
                // Transition to half-open
                transitionTo(.halfOpen)
                halfOpenAttempts = 0
                return true
            }
            return false
            
        case .halfOpen:
            // Allow limited attempts in half-open state
            if halfOpenAttempts < configuration.halfOpenMaxAttempts {
                halfOpenAttempts += 1
                return true
            }
            return false
        }
    }
    
    private func recordSuccess(duration: TimeInterval) {
        successfulRequests += 1
        lastSuccessTime = Date()
        consecutiveSuccesses += 1
        consecutiveFailures = 0
        
        // Store response time
        responseTimes.append(duration)
        if responseTimes.count > 100 {
            responseTimes.removeFirst()
        }
        
        logger.debug("[\(name)] Request succeeded (duration: \(duration)s)")
        
        // Handle state transitions
        switch state {
        case .halfOpen:
            if consecutiveSuccesses >= configuration.successThreshold {
                // Circuit has recovered
                transitionTo(.closed)
                currentBackoffMultiplier = 1
            }
            
        case .open:
            // Should not happen, but handle gracefully
            transitionTo(.halfOpen)
            
        case .closed:
            // Reset backoff multiplier on success
            if consecutiveSuccesses >= configuration.successThreshold {
                currentBackoffMultiplier = 1
            }
        }
        
        // Notify handler
        requestHandler?(getStatistics())
    }
    
    private func recordFailure(error: Error, duration: TimeInterval) {
        failedRequests += 1
        lastFailureTime = Date()
        consecutiveFailures += 1
        consecutiveSuccesses = 0
        
        // Store response time
        responseTimes.append(duration)
        if responseTimes.count > 100 {
            responseTimes.removeFirst()
        }
        
        logger.warning("[\(name)] Request failed: \(error.localizedDescription)")
        
        // Handle state transitions
        switch state {
        case .closed:
            if consecutiveFailures >= configuration.failureThreshold {
                // Open the circuit
                let resetTimeout = calculateResetTimeout()
                let resetTime = Date().addingTimeInterval(resetTimeout)
                transitionTo(.open(until: resetTime))
            }
            
        case .halfOpen:
            // Single failure in half-open state opens the circuit again
            let resetTimeout = calculateResetTimeout()
            let resetTime = Date().addingTimeInterval(resetTimeout)
            transitionTo(.open(until: resetTime))
            halfOpenAttempts = 0
            
        case .open:
            // Already open, no action needed
            break
        }
        
        // Notify handler
        requestHandler?(getStatistics())
    }
    
    private func transitionTo(_ newState: State) {
        let oldState = state
        state = newState
        stateChanges += 1
        
        logger.info("[\(name)] State transition: \(oldState.description) -> \(newState.description)")
        
        // Notify handler
        stateChangeHandler?(oldState, newState)
    }
    
    private func calculateResetTimeout() -> TimeInterval {
        if configuration.exponentialBackoff {
            let timeout = configuration.resetTimeout * Double(currentBackoffMultiplier)
            currentBackoffMultiplier = min(currentBackoffMultiplier * 2, 16) // Cap at 16x
            return min(timeout, configuration.maxResetTimeout)
        } else {
            return configuration.resetTimeout
        }
    }
    
    private func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CircuitBreakerError.requestTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Circuit Breaker Manager

/// Manager for multiple circuit breakers
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor CircuitBreakerManager {
    
    // MARK: - Properties
    
    private var breakers: [String: CircuitBreaker] = [:]
    private let defaultConfiguration: CircuitBreaker.Configuration
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "CircuitBreakerManager")
    
    // MARK: - Initialization
    
    public init(defaultConfiguration: CircuitBreaker.Configuration = .default) {
        self.defaultConfiguration = defaultConfiguration
    }
    
    // MARK: - Public Methods
    
    /// Get or create circuit breaker
    public func breaker(
        for name: String,
        configuration: CircuitBreaker.Configuration? = nil
    ) -> CircuitBreaker {
        if let existingBreaker = breakers[name] {
            return existingBreaker
        }
        
        let newBreaker = CircuitBreaker(
            name: name,
            configuration: configuration ?? defaultConfiguration
        )
        
        breakers[name] = newBreaker
        logger.info("Created circuit breaker: \(name)")
        
        return newBreaker
    }
    
    /// Execute request through circuit breaker
    public func execute<T>(
        name: String,
        timeout: TimeInterval? = nil,
        configuration: CircuitBreaker.Configuration? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let breaker = self.breaker(for: name, configuration: configuration)
        return try await breaker.execute(timeout: timeout, operation: operation)
    }
    
    /// Get all circuit breakers
    public func getAllBreakers() -> [String: CircuitBreaker] {
        return breakers
    }
    
    /// Get statistics for all breakers
    public func getAllStatistics() async -> [String: CircuitBreaker.Statistics] {
        var statistics: [String: CircuitBreaker.Statistics] = [:]
        
        for (name, breaker) in breakers {
            statistics[name] = await breaker.getStatistics()
        }
        
        return statistics
    }
    
    /// Reset specific breaker
    public func reset(name: String) async {
        if let breaker = breakers[name] {
            await breaker.reset()
            logger.info("Reset circuit breaker: \(name)")
        }
    }
    
    /// Reset all breakers
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
        logger.info("Reset all circuit breakers")
    }
    
    /// Remove circuit breaker
    public func remove(name: String) {
        breakers.removeValue(forKey: name)
        logger.info("Removed circuit breaker: \(name)")
    }
    
    /// Remove all circuit breakers
    public func removeAll() {
        breakers.removeAll()
        logger.info("Removed all circuit breakers")
    }
}

// MARK: - Health Check

/// Health check for services
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor HealthChecker {
    
    // MARK: - Types
    
    /// Health status
    public enum HealthStatus {
        case healthy
        case degraded
        case unhealthy
        
        public var emoji: String {
            switch self {
            case .healthy: return "✅"
            case .degraded: return "⚠️"
            case .unhealthy: return "❌"
            }
        }
    }
    
    /// Health check result
    public struct HealthCheckResult {
        public let service: String
        public let status: HealthStatus
        public let responseTime: TimeInterval?
        public let message: String?
        public let timestamp: Date
        public let metadata: [String: Any]?
    }
    
    /// Health check configuration
    public struct Configuration {
        public let interval: TimeInterval
        public let timeout: TimeInterval
        public let retries: Int
        public let degradedThreshold: TimeInterval
        public let unhealthyThreshold: TimeInterval
        
        public init(
            interval: TimeInterval = 30,
            timeout: TimeInterval = 10,
            retries: Int = 3,
            degradedThreshold: TimeInterval = 2,
            unhealthyThreshold: TimeInterval = 5
        ) {
            self.interval = interval
            self.timeout = timeout
            self.retries = retries
            self.degradedThreshold = degradedThreshold
            self.unhealthyThreshold = unhealthyThreshold
        }
    }
    
    /// Health check endpoint
    public struct HealthEndpoint {
        public let name: String
        public let url: URL
        public let method: String
        public let headers: [String: String]?
        public let expectedStatusCode: Int
        public let validator: ((Data) -> Bool)?
        
        public init(
            name: String,
            url: URL,
            method: String = "GET",
            headers: [String: String]? = nil,
            expectedStatusCode: Int = 200,
            validator: ((Data) -> Bool)? = nil
        ) {
            self.name = name
            self.url = url
            self.method = method
            self.headers = headers
            self.expectedStatusCode = expectedStatusCode
            self.validator = validator
        }
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private var endpoints: [HealthEndpoint] = []
    private var lastResults: [String: HealthCheckResult] = [:]
    private var checkTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "HealthCheck")
    
    private var statusChangeHandler: ((String, HealthStatus) -> Void)?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    deinit {
        checkTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Add health check endpoint
    public func addEndpoint(_ endpoint: HealthEndpoint) {
        endpoints.append(endpoint)
        logger.info("Added health check endpoint: \(endpoint.name)")
    }
    
    /// Remove health check endpoint
    public func removeEndpoint(name: String) {
        endpoints.removeAll { $0.name == name }
        lastResults.removeValue(forKey: name)
        logger.info("Removed health check endpoint: \(name)")
    }
    
    /// Start health checks
    public func start() {
        guard checkTask == nil else { return }
        
        checkTask = Task {
            while !Task.isCancelled {
                await performHealthChecks()
                try? await Task.sleep(nanoseconds: UInt64(configuration.interval * 1_000_000_000))
            }
        }
        
        logger.info("Started health checks")
    }
    
    /// Stop health checks
    public func stop() {
        checkTask?.cancel()
        checkTask = nil
        logger.info("Stopped health checks")
    }
    
    /// Perform health check immediately
    public func checkNow() async -> [HealthCheckResult] {
        return await performHealthChecks()
    }
    
    /// Get last results
    public func getLastResults() -> [HealthCheckResult] {
        return Array(lastResults.values).sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get overall health status
    public func getOverallStatus() -> HealthStatus {
        let statuses = lastResults.values.map { $0.status }
        
        if statuses.contains(.unhealthy) {
            return .unhealthy
        } else if statuses.contains(.degraded) {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    /// Set status change handler
    public func onStatusChange(_ handler: @escaping (String, HealthStatus) -> Void) {
        self.statusChangeHandler = handler
    }
    
    // MARK: - Private Methods
    
    @discardableResult
    private func performHealthChecks() async -> [HealthCheckResult] {
        var results: [HealthCheckResult] = []
        
        await withTaskGroup(of: HealthCheckResult.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await self.checkEndpoint(endpoint)
                }
            }
            
            for await result in group {
                results.append(result)
                
                // Check for status change
                if let previousResult = lastResults[result.service],
                   previousResult.status != result.status {
                    statusChangeHandler?(result.service, result.status)
                    logger.info("Health status changed for \(result.service): \(previousResult.status) -> \(result.status)")
                }
                
                lastResults[result.service] = result
            }
        }
        
        return results
    }
    
    private func checkEndpoint(_ endpoint: HealthEndpoint) async -> HealthCheckResult {
        let startTime = Date()
        var lastError: Error?
        
        for attempt in 0..<configuration.retries {
            do {
                var request = URLRequest(url: endpoint.url)
                request.httpMethod = endpoint.method
                request.timeoutInterval = configuration.timeout
                endpoint.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                let responseTime = Date().timeIntervalSince(startTime)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                // Check status code
                guard httpResponse.statusCode == endpoint.expectedStatusCode else {
                    throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: data)
                }
                
                // Run custom validator if provided
                if let validator = endpoint.validator {
                    guard validator(data) else {
                        throw NetworkError.validationFailed("Custom validation failed")
                    }
                }
                
                // Determine health status based on response time
                let status: HealthStatus
                if responseTime > configuration.unhealthyThreshold {
                    status = .unhealthy
                } else if responseTime > configuration.degradedThreshold {
                    status = .degraded
                } else {
                    status = .healthy
                }
                
                return HealthCheckResult(
                    service: endpoint.name,
                    status: status,
                    responseTime: responseTime,
                    message: nil,
                    timestamp: Date(),
                    metadata: nil
                )
                
            } catch {
                lastError = error
                
                if attempt < configuration.retries - 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
            }
        }
        
        // All retries failed
        return HealthCheckResult(
            service: endpoint.name,
            status: .unhealthy,
            responseTime: nil,
            message: lastError?.localizedDescription ?? "Health check failed",
            timestamp: Date(),
            metadata: nil
        )
    }
}