import Foundation
import os.log

/// Mock URL protocol for testing
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class MockURLProtocol: URLProtocol {
    
    // MARK: - Types
    
    /// Mock response configuration
    public struct MockResponse {
        public let data: Data?
        public let response: URLResponse?
        public let error: Error?
        public let delay: TimeInterval
        public let validator: ((URLRequest) -> Bool)?
        
        public init(
            data: Data? = nil,
            response: URLResponse? = nil,
            error: Error? = nil,
            delay: TimeInterval = 0,
            validator: ((URLRequest) -> Bool)? = nil
        ) {
            self.data = data
            self.response = response
            self.error = error
            self.delay = delay
            self.validator = validator
        }
        
        /// Success response
        public static func success(
            data: Data,
            statusCode: Int = 200,
            headers: [String: String] = [:],
            delay: TimeInterval = 0
        ) -> MockResponse {
            let response = HTTPURLResponse(
                url: URL(string: "https://mock.example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
            return MockResponse(data: data, response: response, delay: delay)
        }
        
        /// JSON success response
        public static func json<T: Encodable>(
            _ object: T,
            statusCode: Int = 200,
            encoder: JSONEncoder = JSONEncoder(),
            delay: TimeInterval = 0
        ) throws -> MockResponse {
            let data = try encoder.encode(object)
            var headers = ["Content-Type": "application/json"]
            headers["Content-Length"] = String(data.count)
            
            return success(data: data, statusCode: statusCode, headers: headers, delay: delay)
        }
        
        /// Error response
        public static func error(
            _ error: Error,
            delay: TimeInterval = 0
        ) -> MockResponse {
            return MockResponse(error: error, delay: delay)
        }
        
        /// Network error response
        public static func networkError(
            code: URLError.Code = .notConnectedToInternet,
            delay: TimeInterval = 0
        ) -> MockResponse {
            let error = URLError(code)
            return MockResponse(error: error, delay: delay)
        }
        
        /// HTTP error response
        public static func httpError(
            statusCode: Int,
            data: Data? = nil,
            delay: TimeInterval = 0
        ) -> MockResponse {
            let response = HTTPURLResponse(
                url: URL(string: "https://mock.example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
            return MockResponse(data: data, response: response, delay: delay)
        }
    }
    
    /// Mock request handler
    public typealias RequestHandler = (URLRequest) -> MockResponse
    
    // MARK: - Static Properties
    
    private static var mockResponses: [String: MockResponse] = [:]
    private static var requestHandlers: [RequestHandler] = []
    private static var requestHistory: [URLRequest] = []
    private static var requestCount: [String: Int] = [:]
    private static let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Mock")
    
    // MARK: - Public Methods
    
    /// Register mock protocol
    public static func register() {
        URLProtocol.registerClass(MockURLProtocol.self)
        logger.info("Registered MockURLProtocol")
    }
    
    /// Unregister mock protocol
    public static func unregister() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        clearAll()
        logger.info("Unregistered MockURLProtocol")
    }
    
    /// Add mock response for URL
    public static func mockResponse(for url: URL, response: MockResponse) {
        mockResponses[url.absoluteString] = response
        logger.debug("Added mock response for: \(url.absoluteString)")
    }
    
    /// Add mock response for URL pattern
    public static func mockResponse(pattern: String, response: MockResponse) {
        mockResponses[pattern] = response
        logger.debug("Added mock response for pattern: \(pattern)")
    }
    
    /// Add request handler
    public static func addRequestHandler(_ handler: @escaping RequestHandler) {
        requestHandlers.append(handler)
        logger.debug("Added request handler")
    }
    
    /// Get request history
    public static func getRequestHistory() -> [URLRequest] {
        return requestHistory
    }
    
    /// Get request count for URL
    public static func getRequestCount(for url: URL) -> Int {
        return requestCount[url.absoluteString] ?? 0
    }
    
    /// Clear all mocks
    public static func clearAll() {
        mockResponses.removeAll()
        requestHandlers.removeAll()
        requestHistory.removeAll()
        requestCount.removeAll()
        logger.debug("Cleared all mock data")
    }
    
    /// Clear request history
    public static func clearHistory() {
        requestHistory.removeAll()
        requestCount.removeAll()
        logger.debug("Cleared request history")
    }
    
    // MARK: - URLProtocol Methods
    
    public override class func canInit(with request: URLRequest) -> Bool {
        // Check if we have a mock for this request
        guard let url = request.url else { return false }
        
        // Check exact URL match
        if mockResponses[url.absoluteString] != nil {
            return true
        }
        
        // Check pattern match
        for (pattern, _) in mockResponses {
            if matchesPattern(url: url, pattern: pattern) {
                return true
            }
        }
        
        // Check request handlers
        if !requestHandlers.isEmpty {
            return true
        }
        
        return false
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        // Record request
        Self.requestHistory.append(request)
        
        if let url = request.url {
            Self.requestCount[url.absoluteString, default: 0] += 1
        }
        
        // Find mock response
        let mockResponse = findMockResponse(for: request)
        
        // Apply delay if needed
        if mockResponse.delay > 0 {
            Thread.sleep(forTimeInterval: mockResponse.delay)
        }
        
        // Send response
        if let error = mockResponse.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = mockResponse.response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            
            if let data = mockResponse.data {
                client?.urlProtocol(self, didLoad: data)
            }
            
            client?.urlProtocolDidFinishLoading(self)
        }
        
        Self.logger.debug("Handled mock request: \(request.url?.absoluteString ?? "nil")")
    }
    
    public override func stopLoading() {
        // Nothing to do
    }
    
    // MARK: - Private Methods
    
    private func findMockResponse(for request: URLRequest) -> MockResponse {
        guard let url = request.url else {
            return MockResponse(error: URLError(.badURL))
        }
        
        // Check exact URL match
        if let response = Self.mockResponses[url.absoluteString] {
            if let validator = response.validator {
                if validator(request) {
                    return response
                }
            } else {
                return response
            }
        }
        
        // Check pattern match
        for (pattern, response) in Self.mockResponses {
            if Self.matchesPattern(url: url, pattern: pattern) {
                if let validator = response.validator {
                    if validator(request) {
                        return response
                    }
                } else {
                    return response
                }
            }
        }
        
        // Check request handlers
        for handler in Self.requestHandlers {
            let response = handler(request)
            if let validator = response.validator {
                if validator(request) {
                    return response
                }
            } else {
                return response
            }
        }
        
        // Default error response
        return MockResponse(error: URLError(.cannotFindHost))
    }
    
    private static func matchesPattern(url: URL, pattern: String) -> Bool {
        // Simple pattern matching (can be enhanced)
        if pattern.contains("*") {
            let regexPattern = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            
            if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") {
                let range = NSRange(location: 0, length: url.absoluteString.count)
                return regex.firstMatch(in: url.absoluteString, range: range) != nil
            }
        }
        
        return url.absoluteString == pattern
    }
}

// MARK: - Mock Session

/// Mock URL session for testing
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class MockURLSession: URLSession {
    
    private let mockDataTask: MockURLSessionDataTask
    
    public init(mockDataTask: MockURLSessionDataTask = MockURLSessionDataTask()) {
        self.mockDataTask = mockDataTask
        super.init()
    }
    
    public override func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        mockDataTask.completionHandler = completionHandler
        mockDataTask.request = request
        return mockDataTask
    }
    
    public override func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let request = URLRequest(url: url)
        return dataTask(with: request, completionHandler: completionHandler)
    }
}

/// Mock URL session data task
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class MockURLSessionDataTask: URLSessionDataTask {
    
    public var mockData: Data?
    public var mockResponse: URLResponse?
    public var mockError: Error?
    public var resumeWasCalled = false
    public var cancelWasCalled = false
    
    var completionHandler: ((Data?, URLResponse?, Error?) -> Void)?
    var request: URLRequest?
    
    public override func resume() {
        resumeWasCalled = true
        completionHandler?(mockData, mockResponse, mockError)
    }
    
    public override func cancel() {
        cancelWasCalled = true
    }
}

// MARK: - Test Helpers

/// Network test helpers
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct NetworkTestHelpers {
    
    /// Create mock JSON data
    public static func mockJSON<T: Encodable>(_ object: T) throws -> Data {
        return try JSONEncoder().encode(object)
    }
    
    /// Create mock response
    public static func mockResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse? {
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )
    }
    
    /// Create mock error
    public static func mockError(code: URLError.Code = .unknown) -> URLError {
        return URLError(code)
    }
    
    /// Assert requests are equal
    public static func assertRequestsEqual(
        _ request1: URLRequest?,
        _ request2: URLRequest?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        assert(request1?.url == request2?.url, "URLs don't match", file: file, line: line)
        assert(request1?.httpMethod == request2?.httpMethod, "Methods don't match", file: file, line: line)
        assert(request1?.allHTTPHeaderFields == request2?.allHTTPHeaderFields, "Headers don't match", file: file, line: line)
        assert(request1?.httpBody == request2?.httpBody, "Bodies don't match", file: file, line: line)
    }
    
    /// Wait for expectation
    public static func wait(
        for duration: TimeInterval = 0.1,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }
}

// MARK: - Request Recorder

/// Records network requests for testing
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor RequestRecorder {
    
    /// Recorded request
    public struct RecordedRequest {
        public let request: URLRequest
        public let response: URLResponse?
        public let data: Data?
        public let error: Error?
        public let timestamp: Date
        public let duration: TimeInterval
    }
    
    private var recordings: [RecordedRequest] = []
    private var isRecording = false
    
    /// Start recording
    public func startRecording() {
        isRecording = true
        recordings.removeAll()
    }
    
    /// Stop recording
    public func stopRecording() {
        isRecording = false
    }
    
    /// Record request
    public func record(
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        error: Error?,
        duration: TimeInterval
    ) {
        guard isRecording else { return }
        
        let recording = RecordedRequest(
            request: request,
            response: response,
            data: data,
            error: error,
            timestamp: Date(),
            duration: duration
        )
        
        recordings.append(recording)
    }
    
    /// Get recordings
    public func getRecordings() -> [RecordedRequest] {
        return recordings
    }
    
    /// Clear recordings
    public func clearRecordings() {
        recordings.removeAll()
    }
    
    /// Export recordings as mocks
    public func exportAsMocks() -> [String: MockURLProtocol.MockResponse] {
        var mocks: [String: MockURLProtocol.MockResponse] = [:]
        
        for recording in recordings {
            guard let url = recording.request.url else { continue }
            
            let mockResponse = MockURLProtocol.MockResponse(
                data: recording.data,
                response: recording.response,
                error: recording.error,
                delay: recording.duration
            )
            
            mocks[url.absoluteString] = mockResponse
        }
        
        return mocks
    }
}