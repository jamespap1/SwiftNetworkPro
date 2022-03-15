import Foundation
import os.log

/// Batch request manager for executing multiple requests efficiently
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor BatchRequestManager {
    
    // MARK: - Types
    
    /// Batch request configuration
    public struct Configuration {
        public let maxConcurrentRequests: Int
        public let timeout: TimeInterval
        public let retryPolicy: RetryPolicy
        public let priorityQueue: Bool
        public let continueOnError: Bool
        public let progressReporting: Bool
        
        public init(
            maxConcurrentRequests: Int = 5,
            timeout: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default,
            priorityQueue: Bool = false,
            continueOnError: Bool = true,
            progressReporting: Bool = true
        ) {
            self.maxConcurrentRequests = maxConcurrentRequests
            self.timeout = timeout
            self.retryPolicy = retryPolicy
            self.priorityQueue = priorityQueue
            self.continueOnError = continueOnError
            self.progressReporting = progressReporting
        }
        
        public static let `default` = Configuration()
        
        public static let highThroughput = Configuration(
            maxConcurrentRequests: 10,
            timeout: 60,
            continueOnError: true
        )
        
        public static let reliable = Configuration(
            maxConcurrentRequests: 3,
            timeout: 45,
            retryPolicy: .aggressive,
            continueOnError: false
        )
    }
    
    /// Retry policy for batch requests
    public struct RetryPolicy {
        public let maxRetries: Int
        public let retryDelay: TimeInterval
        public let exponentialBackoff: Bool
        
        public init(
            maxRetries: Int = 3,
            retryDelay: TimeInterval = 1.0,
            exponentialBackoff: Bool = true
        ) {
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
            self.exponentialBackoff = exponentialBackoff
        }
        
        public static let `default` = RetryPolicy()
        public static let aggressive = RetryPolicy(maxRetries: 5, retryDelay: 0.5)
        public static let none = RetryPolicy(maxRetries: 0)
    }
    
    /// Batch request item
    public struct BatchRequest {
        public let id: String
        public let request: URLRequest
        public let priority: Int
        public let retryPolicy: RetryPolicy?
        public let completionHandler: ((Result<(Data, URLResponse), Error>) -> Void)?
        
        public init(
            id: String = UUID().uuidString,
            request: URLRequest,
            priority: Int = 0,
            retryPolicy: RetryPolicy? = nil,
            completionHandler: ((Result<(Data, URLResponse), Error>) -> Void)? = nil
        ) {
            self.id = id
            self.request = request
            self.priority = priority
            self.retryPolicy = retryPolicy
            self.completionHandler = completionHandler
        }
    }
    
    /// Batch response
    public struct BatchResponse {
        public let id: String
        public let result: Result<(Data, URLResponse), Error>
        public let duration: TimeInterval
        public let retryCount: Int
    }
    
    /// Batch execution result
    public struct BatchResult {
        public let responses: [BatchResponse]
        public let totalDuration: TimeInterval
        public let successCount: Int
        public let failureCount: Int
        public let averageResponseTime: TimeInterval
        
        public var successRate: Double {
            let total = successCount + failureCount
            return total > 0 ? Double(successCount) / Double(total) : 0
        }
    }
    
    /// Batch progress
    public struct BatchProgress {
        public let totalRequests: Int
        public let completedRequests: Int
        public let failedRequests: Int
        public let inProgressRequests: Int
        public let estimatedTimeRemaining: TimeInterval?
        
        public var progress: Double {
            return totalRequests > 0 ? Double(completedRequests) / Double(totalRequests) : 0
        }
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let session: URLSession
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Batch")
    
    private var queue: [BatchRequest] = []
    private var inProgress: [String: Task<BatchResponse, Never>] = [:]
    private var completed: [BatchResponse] = []
    
    private var progressHandler: ((BatchProgress) -> Void)?
    private var batchStartTime: Date?
    
    // MARK: - Initialization
    
    public init(
        configuration: Configuration = .default,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }
    
    // MARK: - Public Methods
    
    /// Add request to batch
    public func addRequest(_ request: BatchRequest) {
        queue.append(request)
        
        if configuration.priorityQueue {
            queue.sort { $0.priority > $1.priority }
        }
        
        logger.debug("Added request to batch: \(request.id)")
    }
    
    /// Add multiple requests to batch
    public func addRequests(_ requests: [BatchRequest]) {
        queue.append(contentsOf: requests)
        
        if configuration.priorityQueue {
            queue.sort { $0.priority > $1.priority }
        }
        
        logger.debug("Added \(requests.count) requests to batch")
    }
    
    /// Execute batch requests
    public func execute() async -> BatchResult {
        batchStartTime = Date()
        completed.removeAll()
        
        logger.info("Starting batch execution with \(queue.count) requests")
        
        await withTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            
            while !queue.isEmpty || activeTasks > 0 {
                // Start new tasks up to the concurrent limit
                while activeTasks < configuration.maxConcurrentRequests && !queue.isEmpty {
                    let request = queue.removeFirst()
                    activeTasks += 1
                    
                    group.addTask {
                        await self.executeRequest(request)
                        await self.taskCompleted()
                    }
                }
                
                // Wait for at least one task to complete
                if activeTasks > 0 {
                    await group.next()
                    activeTasks -= 1
                }
                
                // Report progress
                await reportProgress()
            }
        }
        
        let totalDuration = Date().timeIntervalSince(batchStartTime!)
        
        let successCount = completed.filter { result in
            if case .success = result.result {
                return true
            }
            return false
        }.count
        
        let failureCount = completed.count - successCount
        
        let averageResponseTime = completed.isEmpty ? 0 : 
            completed.map { $0.duration }.reduce(0, +) / Double(completed.count)
        
        let result = BatchResult(
            responses: completed,
            totalDuration: totalDuration,
            successCount: successCount,
            failureCount: failureCount,
            averageResponseTime: averageResponseTime
        )
        
        logger.info("Batch execution completed: \(successCount) succeeded, \(failureCount) failed, avg time: \(averageResponseTime)s")
        
        return result
    }
    
    /// Execute batch requests with custom type
    public func execute<T: Decodable>(
        decoder: JSONDecoder = JSONDecoder(),
        as type: T.Type = T.self
    ) async -> [(id: String, result: Result<T, Error>)] {
        let batchResult = await execute()
        
        return batchResult.responses.map { response in
            let decodedResult: Result<T, Error>
            
            switch response.result {
            case .success(let (data, _)):
                do {
                    let decoded = try decoder.decode(T.self, from: data)
                    decodedResult = .success(decoded)
                } catch {
                    decodedResult = .failure(error)
                }
            case .failure(let error):
                decodedResult = .failure(error)
            }
            
            return (id: response.id, result: decodedResult)
        }
    }
    
    /// Cancel all pending requests
    public func cancelAll() {
        queue.removeAll()
        
        for task in inProgress.values {
            task.cancel()
        }
        inProgress.removeAll()
        
        logger.info("Cancelled all batch requests")
    }
    
    /// Set progress handler
    public func onProgress(_ handler: @escaping (BatchProgress) -> Void) {
        self.progressHandler = handler
    }
    
    /// Get current batch size
    public func getBatchSize() -> Int {
        return queue.count + inProgress.count
    }
    
    /// Clear completed responses
    public func clearCompleted() {
        completed.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func executeRequest(_ batchRequest: BatchRequest) async {
        let startTime = Date()
        var retryCount = 0
        let retryPolicy = batchRequest.retryPolicy ?? configuration.retryPolicy
        
        var lastError: Error?
        
        while retryCount <= retryPolicy.maxRetries {
            do {
                var request = batchRequest.request
                request.timeoutInterval = configuration.timeout
                
                let (data, response) = try await session.data(for: request)
                
                // Validate response
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: data)
                    }
                }
                
                let duration = Date().timeIntervalSince(startTime)
                
                let batchResponse = BatchResponse(
                    id: batchRequest.id,
                    result: .success((data, response)),
                    duration: duration,
                    retryCount: retryCount
                )
                
                completed.append(batchResponse)
                
                // Call completion handler if provided
                batchRequest.completionHandler?(.success((data, response)))
                
                logger.debug("Request \(batchRequest.id) completed successfully")
                return
                
            } catch {
                lastError = error
                
                if retryCount < retryPolicy.maxRetries {
                    // Calculate retry delay
                    let delay: TimeInterval
                    if retryPolicy.exponentialBackoff {
                        delay = retryPolicy.retryDelay * pow(2.0, Double(retryCount))
                    } else {
                        delay = retryPolicy.retryDelay
                    }
                    
                    logger.debug("Request \(batchRequest.id) failed, retrying in \(delay)s")
                    
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    retryCount += 1
                } else {
                    break
                }
            }
        }
        
        // Request failed after all retries
        let duration = Date().timeIntervalSince(startTime)
        
        let batchResponse = BatchResponse(
            id: batchRequest.id,
            result: .failure(lastError ?? NetworkError.unknown),
            duration: duration,
            retryCount: retryCount
        )
        
        completed.append(batchResponse)
        
        // Call completion handler if provided
        batchRequest.completionHandler?(.failure(lastError ?? NetworkError.unknown))
        
        logger.error("Request \(batchRequest.id) failed after \(retryCount) retries: \(lastError?.localizedDescription ?? "Unknown error")")
        
        // Check if we should continue on error
        if !configuration.continueOnError {
            await cancelAll()
        }
    }
    
    private func taskCompleted() {
        // Cleanup completed task
    }
    
    private func reportProgress() {
        guard configuration.progressReporting,
              let progressHandler = progressHandler else {
            return
        }
        
        let totalRequests = queue.count + inProgress.count + completed.count
        let completedRequests = completed.count
        let failedRequests = completed.filter { response in
            if case .failure = response.result {
                return true
            }
            return false
        }.count
        let inProgressRequests = inProgress.count
        
        // Estimate time remaining
        let estimatedTimeRemaining: TimeInterval?
        if let startTime = batchStartTime, completedRequests > 0 {
            let elapsedTime = Date().timeIntervalSince(startTime)
            let averageTimePerRequest = elapsedTime / Double(completedRequests)
            let remainingRequests = totalRequests - completedRequests
            estimatedTimeRemaining = averageTimePerRequest * Double(remainingRequests)
        } else {
            estimatedTimeRemaining = nil
        }
        
        let progress = BatchProgress(
            totalRequests: totalRequests,
            completedRequests: completedRequests,
            failedRequests: failedRequests,
            inProgressRequests: inProgressRequests,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
        
        progressHandler(progress)
    }
}

// MARK: - Batch Request Builder

/// Builder for creating batch requests
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class BatchRequestBuilder {
    
    private var requests: [BatchRequestManager.BatchRequest] = []
    
    public init() {}
    
    /// Add GET request
    @discardableResult
    public func get(
        _ url: URL,
        headers: [String: String]? = nil,
        priority: Int = 0,
        id: String? = nil
    ) -> Self {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let batchRequest = BatchRequestManager.BatchRequest(
            id: id ?? UUID().uuidString,
            request: request,
            priority: priority
        )
        
        requests.append(batchRequest)
        return self
    }
    
    /// Add POST request
    @discardableResult
    public func post(
        _ url: URL,
        body: Data? = nil,
        headers: [String: String]? = nil,
        priority: Int = 0,
        id: String? = nil
    ) -> Self {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let batchRequest = BatchRequestManager.BatchRequest(
            id: id ?? UUID().uuidString,
            request: request,
            priority: priority
        )
        
        requests.append(batchRequest)
        return self
    }
    
    /// Add PUT request
    @discardableResult
    public func put(
        _ url: URL,
        body: Data? = nil,
        headers: [String: String]? = nil,
        priority: Int = 0,
        id: String? = nil
    ) -> Self {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let batchRequest = BatchRequestManager.BatchRequest(
            id: id ?? UUID().uuidString,
            request: request,
            priority: priority
        )
        
        requests.append(batchRequest)
        return self
    }
    
    /// Add DELETE request
    @discardableResult
    public func delete(
        _ url: URL,
        headers: [String: String]? = nil,
        priority: Int = 0,
        id: String? = nil
    ) -> Self {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let batchRequest = BatchRequestManager.BatchRequest(
            id: id ?? UUID().uuidString,
            request: request,
            priority: priority
        )
        
        requests.append(batchRequest)
        return self
    }
    
    /// Add custom request
    @discardableResult
    public func custom(
        _ request: URLRequest,
        priority: Int = 0,
        id: String? = nil
    ) -> Self {
        let batchRequest = BatchRequestManager.BatchRequest(
            id: id ?? UUID().uuidString,
            request: request,
            priority: priority
        )
        
        requests.append(batchRequest)
        return self
    }
    
    /// Build batch requests
    public func build() -> [BatchRequestManager.BatchRequest] {
        return requests
    }
    
    /// Execute with batch manager
    public func execute(
        with manager: BatchRequestManager
    ) async -> BatchRequestManager.BatchResult {
        await manager.addRequests(requests)
        return await manager.execute()
    }
}