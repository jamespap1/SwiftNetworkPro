import Foundation
import os.log

/// Main networking client for SwiftNetwork Pro
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor NetworkClient {
    
    // MARK: - Properties
    
    /// Shared singleton instance
    public static let shared = NetworkClient()
    
    /// Current configuration
    private var configuration: NetworkConfiguration
    
    /// URL session for requests
    private let session: URLSession
    
    /// Active request tasks
    private var activeTasks: [UUID: URLSessionTask] = [:]
    
    /// Request interceptors
    private var interceptors: [RequestInterceptor] = []
    
    /// Response processors
    private var responseProcessors: [ResponseProcessor] = []
    
    /// Logger
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "NetworkClient")
    
    // MARK: - Initialization
    
    public init(configuration: NetworkConfiguration = .default) {
        self.configuration = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfig.waitsForConnectivity = configuration.waitsForConnectivity
        sessionConfig.allowsCellularAccess = configuration.allowsCellularAccess
        sessionConfig.allowsExpensiveNetworkAccess = configuration.allowsExpensiveNetworkAccess
        sessionConfig.allowsConstrainedNetworkAccess = configuration.allowsConstrainedNetworkAccess
        sessionConfig.requestCachePolicy = configuration.cachePolicy.urlCachePolicy
        
        if let urlCache = configuration.urlCache {
            sessionConfig.urlCache = urlCache
        }
        
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - Public Methods
    
    /// Perform a GET request
    public func get<T: Decodable>(
        _ endpoint: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        return try await request(
            endpoint,
            method: .get,
            parameters: parameters,
            headers: headers,
            as: type
        )
    }
    
    /// Perform a POST request
    public func post<T: Decodable, B: Encodable>(
        _ endpoint: String,
        body: B? = nil,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        return try await request(
            endpoint,
            method: .post,
            parameters: parameters,
            body: body,
            headers: headers,
            as: type
        )
    }
    
    /// Perform a PUT request
    public func put<T: Decodable, B: Encodable>(
        _ endpoint: String,
        body: B? = nil,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        return try await request(
            endpoint,
            method: .put,
            parameters: parameters,
            body: body,
            headers: headers,
            as: type
        )
    }
    
    /// Perform a PATCH request
    public func patch<T: Decodable, B: Encodable>(
        _ endpoint: String,
        body: B? = nil,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        return try await request(
            endpoint,
            method: .patch,
            parameters: parameters,
            body: body,
            headers: headers,
            as: type
        )
    }
    
    /// Perform a DELETE request
    public func delete<T: Decodable>(
        _ endpoint: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        return try await request(
            endpoint,
            method: .delete,
            parameters: parameters,
            headers: headers,
            as: type
        )
    }
    
    /// Perform a generic request
    public func request<T: Decodable, B: Encodable>(
        _ endpoint: String,
        method: HTTPMethod,
        parameters: [String: Any]? = nil,
        body: B? = nil,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        // Build request
        var request = try buildRequest(
            endpoint: endpoint,
            method: method,
            parameters: parameters,
            body: body,
            headers: headers
        )
        
        // Apply interceptors
        for interceptor in interceptors {
            request = try await interceptor.intercept(request)
        }
        
        // Log request
        logRequest(request)
        
        // Perform request
        let requestId = UUID()
        
        do {
            let (data, response) = try await performRequest(request, id: requestId)
            
            // Process response
            var processedData = data
            for processor in responseProcessors {
                processedData = try await processor.process(processedData, response: response)
            }
            
            // Log response
            logResponse(response, data: processedData)
            
            // Validate response
            try validateResponse(response, data: processedData)
            
            // Decode response
            let decoded = try decode(type, from: processedData)
            
            return decoded
            
        } catch {
            // Handle error with retry logic if applicable
            if let networkError = error as? NetworkError,
               networkError.isRetryable,
               configuration.retryPolicy.maxAttempts > 0 {
                return try await retryRequest(
                    request: request,
                    method: method,
                    type: type,
                    attempt: 1,
                    lastError: networkError
                )
            }
            throw error
        }
    }
    
    /// Download a file
    public func download(
        from url: String,
        to destination: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }
        
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = configuration.timeout
        
        // Apply interceptors
        for interceptor in interceptors {
            request = try await interceptor.intercept(request)
        }
        
        let task = session.downloadTask(with: request)
        let requestId = UUID()
        activeTasks[requestId] = task
        
        defer {
            activeTasks[requestId] = nil
        }
        
        do {
            let (tempURL, response) = try await task.download()
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: nil)
            }
            
            // Move file to destination
            try FileManager.default.moveItem(at: tempURL, to: destination)
            
            return destination
        } catch {
            throw error
        }
    }
    
    /// Upload a file
    public func upload<T: Decodable>(
        _ file: URL,
        to endpoint: String,
        method: HTTPMethod = .post,
        headers: [String: String]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        guard let url = URL(string: buildFullURL(endpoint)) else {
            throw NetworkError.invalidURL(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.timeout
        
        // Set headers
        var allHeaders = configuration.defaultHeaders
        headers?.forEach { allHeaders[$0.key] = $0.value }
        allHeaders["Content-Type"] = "multipart/form-data"
        allHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Apply interceptors
        for interceptor in interceptors {
            request = try await interceptor.intercept(request)
        }
        
        let task = session.uploadTask(with: request, fromFile: file)
        let requestId = UUID()
        activeTasks[requestId] = task
        
        defer {
            activeTasks[requestId] = nil
        }
        
        let (data, response) = try await task.upload()
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        try validateResponse(httpResponse, data: data)
        
        return try decode(type, from: data)
    }
    
    /// Cancel all active requests
    public func cancelAllRequests() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        logger.info("Cancelled all active requests")
    }
    
    /// Cancel a specific request
    public func cancelRequest(id: UUID) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks[id] = nil
            logger.info("Cancelled request: \(id)")
        }
    }
    
    /// Update configuration
    public func updateConfiguration(_ configuration: NetworkConfiguration) {
        self.configuration = configuration
        logger.info("Updated network configuration")
    }
    
    /// Add request interceptor
    public func addInterceptor(_ interceptor: RequestInterceptor) {
        interceptors.append(interceptor)
    }
    
    /// Add response processor
    public func addResponseProcessor(_ processor: ResponseProcessor) {
        responseProcessors.append(processor)
    }
    
    // MARK: - Private Methods
    
    private func buildRequest<B: Encodable>(
        endpoint: String,
        method: HTTPMethod,
        parameters: [String: Any]?,
        body: B?,
        headers: [String: String]?
    ) throws -> URLRequest {
        let urlString = buildFullURL(endpoint)
        
        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidURL(endpoint)
        }
        
        // Add query parameters for GET requests
        if method == .get, let parameters = parameters {
            components.queryItems = parameters.map {
                URLQueryItem(name: $0.key, value: "\($0.value)")
            }
        }
        
        guard let url = components.url else {
            throw NetworkError.invalidURL(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.timeout
        
        // Set headers
        var allHeaders = configuration.defaultHeaders
        headers?.forEach { allHeaders[$0.key] = $0.value }
        
        // Set body for non-GET requests
        if method.hasBody {
            if let body = body {
                request.httpBody = try configuration.encoder.encode(body)
                allHeaders["Content-Type"] = "application/json"
            } else if let parameters = parameters {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                allHeaders["Content-Type"] = "application/json"
            }
        }
        
        allHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        return request
    }
    
    private func buildFullURL(_ endpoint: String) -> String {
        // If endpoint is already a full URL, return it
        if endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") {
            return endpoint
        }
        
        // Otherwise, combine with base URL
        let baseURL = configuration.baseURL?.trimmingCharacters(in: .init(charactersIn: "/")) ?? ""
        let cleanEndpoint = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        return baseURL + cleanEndpoint
    }
    
    private func performRequest(_ request: URLRequest, id: UUID) async throws -> (Data, URLResponse) {
        let task = session.dataTask(with: request)
        activeTasks[id] = task
        
        defer {
            activeTasks[id] = nil
        }
        
        return try await task.data()
    }
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw NetworkError.unauthorized(reason: nil)
        case 403:
            throw NetworkError.forbidden
        case 404:
            throw NetworkError.invalidStatusCode(404, data: data)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw NetworkError.tooManyRequests(retryAfter: retryAfter)
        case 500...599:
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        default:
            throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: data)
        }
    }
    
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try configuration.decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
    
    private func retryRequest<T: Decodable>(
        request: URLRequest,
        method: HTTPMethod,
        type: T.Type,
        attempt: Int,
        lastError: NetworkError
    ) async throws -> T {
        guard attempt <= configuration.retryPolicy.maxAttempts else {
            throw lastError
        }
        
        // Calculate delay based on retry policy
        let delay = configuration.retryPolicy.delay(for: attempt)
        
        logger.info("Retrying request (attempt \(attempt)/\(configuration.retryPolicy.maxAttempts)) after \(delay) seconds")
        
        // Wait before retrying
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        do {
            let (data, response) = try await performRequest(request, id: UUID())
            try validateResponse(response, data: data)
            return try decode(type, from: data)
        } catch {
            if let networkError = error as? NetworkError,
               networkError.isRetryable {
                return try await retryRequest(
                    request: request,
                    method: method,
                    type: type,
                    attempt: attempt + 1,
                    lastError: networkError
                )
            }
            throw error
        }
    }
    
    private func logRequest(_ request: URLRequest) {
        guard configuration.enableLogging else { return }
        
        logger.debug("""
        🚀 Request: \(request.httpMethod ?? "Unknown") \(request.url?.absoluteString ?? "Unknown URL")
        Headers: \(request.allHTTPHeaderFields ?? [:])
        Body: \(request.httpBody.map { String(data: $0, encoding: .utf8) ?? "Binary data" } ?? "No body")
        """)
    }
    
    private func logResponse(_ response: URLResponse, data: Data) {
        guard configuration.enableLogging else { return }
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("""
            ✅ Response: \(httpResponse.statusCode) \(response.url?.absoluteString ?? "Unknown URL")
            Headers: \(httpResponse.allHeaderFields)
            Body: \(String(data: data, encoding: .utf8) ?? "Binary data")
            """)
        }
    }
}

// MARK: - Extensions

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension URLSessionTask {
    func data() async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self as? URLSessionDataTask
            task?.resume()
            
            // This is a simplified version - in production, you'd need proper delegate handling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Placeholder for actual implementation
                continuation.resume(throwing: NetworkError.unknown(NSError()))
            }
        }
    }
    
    func download() async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self as? URLSessionDownloadTask
            task?.resume()
            
            // This is a simplified version - in production, you'd need proper delegate handling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Placeholder for actual implementation
                continuation.resume(throwing: NetworkError.unknown(NSError()))
            }
        }
    }
    
    func upload() async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self as? URLSessionUploadTask
            task?.resume()
            
            // This is a simplified version - in production, you'd need proper delegate handling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Placeholder for actual implementation
                continuation.resume(throwing: NetworkError.unknown(NSError()))
            }
        }
    }
}// Security update
