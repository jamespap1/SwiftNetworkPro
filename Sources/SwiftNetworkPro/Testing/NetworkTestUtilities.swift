import Foundation
import Network
import Combine
import os.log

/// Comprehensive network testing utilities
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct NetworkTestUtilities {
    
    // MARK: - Mock Server
    
    /// Simple HTTP mock server for testing
    public class MockHTTPServer {
        
        public struct Route {
            public let method: String
            public let path: String
            public let handler: (MockRequest) -> MockResponse
            
            public init(method: String, path: String, handler: @escaping (MockRequest) -> MockResponse) {
                self.method = method
                self.path = path
                self.handler = handler
            }
        }
        
        public struct MockRequest {
            public let method: String
            public let path: String
            public let headers: [String: String]
            public let body: Data?
            public let queryParameters: [String: String]
            
            public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil, queryParameters: [String: String] = [:]) {
                self.method = method
                self.path = path
                self.headers = headers
                self.body = body
                self.queryParameters = queryParameters
            }
        }
        
        public struct MockResponse {
            public let statusCode: Int
            public let headers: [String: String]
            public let body: Data?
            public let delay: TimeInterval?
            
            public init(statusCode: Int = 200, headers: [String: String] = [:], body: Data? = nil, delay: TimeInterval? = nil) {
                self.statusCode = statusCode
                self.headers = headers
                self.body = body
                self.delay = delay
            }
            
            public static func json<T: Encodable>(_ object: T, statusCode: Int = 200, encoder: JSONEncoder = JSONEncoder()) throws -> MockResponse {
                let data = try encoder.encode(object)
                return MockResponse(
                    statusCode: statusCode,
                    headers: ["Content-Type": "application/json"],
                    body: data
                )
            }
            
            public static func text(_ text: String, statusCode: Int = 200) -> MockResponse {
                return MockResponse(
                    statusCode: statusCode,
                    headers: ["Content-Type": "text/plain"],
                    body: text.data(using: .utf8)
                )
            }
            
            public static func error(_ statusCode: Int, message: String = "") -> MockResponse {
                return MockResponse(
                    statusCode: statusCode,
                    body: message.data(using: .utf8)
                )
            }
        }
        
        private var routes: [Route] = []
        private var listener: NWListener?
        private var connections: Set<NWConnection> = []
        private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "MockServer")
        
        public let port: UInt16
        
        public init(port: UInt16 = 0) {
            self.port = port
        }
        
        public func addRoute(method: String, path: String, handler: @escaping (MockRequest) -> MockResponse) {
            routes.append(Route(method: method, path: path, handler: handler))
        }
        
        public func get(_ path: String, handler: @escaping (MockRequest) -> MockResponse) {
            addRoute(method: "GET", path: path, handler: handler)
        }
        
        public func post(_ path: String, handler: @escaping (MockRequest) -> MockResponse) {
            addRoute(method: "POST", path: path, handler: handler)
        }
        
        public func put(_ path: String, handler: @escaping (MockRequest) -> MockResponse) {
            addRoute(method: "PUT", path: path, handler: handler)
        }
        
        public func delete(_ path: String, handler: @escaping (MockRequest) -> MockResponse) {
            addRoute(method: "DELETE", path: path, handler: handler)
        }
        
        public func start() async throws {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global())
            
            logger.info("Mock server started on port \(port)")
        }
        
        public func stop() {
            listener?.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
            logger.info("Mock server stopped")
        }
        
        private func handleConnection(_ connection: NWConnection) {
            connections.insert(connection)
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.connections.remove(connection)
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            receiveRequest(connection)
        }
        
        private func receiveRequest(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    self?.processRequest(data, connection: connection)
                }
                
                if !isComplete {
                    self?.receiveRequest(connection)
                }
            }
        }
        
        private func processRequest(_ data: Data, connection: NWConnection) {
            guard let requestString = String(data: data, encoding: .utf8) else { return }
            
            let lines = requestString.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { return }
            
            let components = requestLine.components(separatedBy: " ")
            guard components.count >= 3 else { return }
            
            let method = components[0]
            let path = components[1]
            
            // Parse headers
            var headers: [String: String] = [:]
            var bodyStartIndex = 0
            
            for (index, line) in lines.enumerated().dropFirst() {
                if line.isEmpty {
                    bodyStartIndex = index + 1
                    break
                }
                
                if let colonIndex = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }
            
            // Extract body
            let bodyLines = Array(lines.dropFirst(bodyStartIndex))
            let bodyString = bodyLines.joined(separator: "\r\n")
            let body = bodyString.isEmpty ? nil : bodyString.data(using: .utf8)
            
            let request = MockRequest(method: method, path: path, headers: headers, body: body)
            let response = findRoute(for: request)?.handler(request) ?? MockResponse(statusCode: 404)
            
            sendResponse(response, to: connection)
        }
        
        private func findRoute(for request: MockRequest) -> Route? {
            return routes.first { route in
                route.method == request.method && route.path == request.path
            }
        }
        
        private func sendResponse(_ response: MockResponse, to connection: NWConnection) {
            var responseString = "HTTP/1.1 \(response.statusCode) OK\r\n"
            
            for (key, value) in response.headers {
                responseString += "\(key): \(value)\r\n"
            }
            
            if let body = response.body {
                responseString += "Content-Length: \(body.count)\r\n"
            }
            
            responseString += "\r\n"
            
            var responseData = responseString.data(using: .utf8) ?? Data()
            if let body = response.body {
                responseData.append(body)
            }
            
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    // MARK: - Network Latency Simulator
    
    /// Simulates network latency and packet loss
    public class NetworkConditionSimulator {
        
        public enum NetworkCondition {
            case perfect
            case wifi
            case cellular3G
            case cellular2G
            case custom(latency: TimeInterval, bandwidth: Double, packetLoss: Double)
            
            var latency: TimeInterval {
                switch self {
                case .perfect: return 0
                case .wifi: return 0.010 // 10ms
                case .cellular3G: return 0.100 // 100ms
                case .cellular2G: return 0.300 // 300ms
                case .custom(let latency, _, _): return latency
                }
            }
            
            var bandwidth: Double {
                switch self {
                case .perfect: return Double.infinity
                case .wifi: return 50_000_000 // 50 Mbps
                case .cellular3G: return 3_000_000 // 3 Mbps
                case .cellular2G: return 250_000 // 250 Kbps
                case .custom(_, let bandwidth, _): return bandwidth
                }
            }
            
            var packetLoss: Double {
                switch self {
                case .perfect: return 0
                case .wifi: return 0.001 // 0.1%
                case .cellular3G: return 0.01 // 1%
                case .cellular2G: return 0.05 // 5%
                case .custom(_, _, let packetLoss): return packetLoss
                }
            }
        }
        
        private let condition: NetworkCondition
        
        public init(condition: NetworkCondition) {
            self.condition = condition
        }
        
        public func simulateRequest<T>(operation: () async throws -> T) async throws -> T {
            // Simulate latency
            if condition.latency > 0 {
                try await Task.sleep(nanoseconds: UInt64(condition.latency * 1_000_000_000))
            }
            
            // Simulate packet loss
            if condition.packetLoss > 0 && Double.random(in: 0...1) < condition.packetLoss {
                throw URLError(.networkConnectionLost)
            }
            
            // Execute operation
            return try await operation()
        }
        
        public func simulateDataTransfer(_ data: Data) async throws -> Data {
            let transferTime = Double(data.count) / condition.bandwidth
            
            if transferTime > 0 {
                try await Task.sleep(nanoseconds: UInt64(transferTime * 1_000_000_000))
            }
            
            return data
        }
    }
    
    // MARK: - Request/Response Capture
    
    /// Captures network requests and responses for testing
    public class NetworkCapture {
        
        public struct CapturedRequest {
            public let request: URLRequest
            public let response: URLResponse?
            public let data: Data?
            public let error: Error?
            public let timestamp: Date
            public let duration: TimeInterval
        }
        
        private var captures: [CapturedRequest] = []
        private var isCapturing = false
        
        public func startCapture() {
            isCapturing = true
            captures.removeAll()
        }
        
        public func stopCapture() {
            isCapturing = false
        }
        
        public func captureRequest(
            _ request: URLRequest,
            response: URLResponse?,
            data: Data?,
            error: Error?,
            duration: TimeInterval
        ) {
            guard isCapturing else { return }
            
            let capture = CapturedRequest(
                request: request,
                response: response,
                data: data,
                error: error,
                timestamp: Date(),
                duration: duration
            )
            
            captures.append(capture)
        }
        
        public func getCaptures() -> [CapturedRequest] {
            return captures
        }
        
        public func clearCaptures() {
            captures.removeAll()
        }
        
        public func exportCaptures() -> Data? {
            let capturesData: [[String: Any]] = captures.map { capture in
                var data: [String: Any] = [:]
                
                data["url"] = capture.request.url?.absoluteString
                data["method"] = capture.request.httpMethod
                data["headers"] = capture.request.allHTTPHeaderFields
                data["timestamp"] = capture.timestamp.timeIntervalSince1970
                data["duration"] = capture.duration
                
                if let response = capture.response as? HTTPURLResponse {
                    data["statusCode"] = response.statusCode
                    data["responseHeaders"] = response.allHeaderFields
                }
                
                if let responseData = capture.data {
                    data["responseBody"] = String(data: responseData, encoding: .utf8)
                }
                
                if let error = capture.error {
                    data["error"] = error.localizedDescription
                }
                
                return data
            }
            
            return try? JSONSerialization.data(withJSONObject: capturesData, options: .prettyPrinted)
        }
    }
    
    // MARK: - Load Testing
    
    /// Simple load testing utility
    public class LoadTester {
        
        public struct LoadTestConfiguration {
            public let numberOfRequests: Int
            public let concurrencyLevel: Int
            public let rampUpTime: TimeInterval
            public let testDuration: TimeInterval?
            
            public init(
                numberOfRequests: Int = 100,
                concurrencyLevel: Int = 10,
                rampUpTime: TimeInterval = 10,
                testDuration: TimeInterval? = nil
            ) {
                self.numberOfRequests = numberOfRequests
                self.concurrencyLevel = concurrencyLevel
                self.rampUpTime = rampUpTime
                self.testDuration = testDuration
            }
        }
        
        public struct LoadTestResult {
            public let totalRequests: Int
            public let successfulRequests: Int
            public let failedRequests: Int
            public let averageResponseTime: TimeInterval
            public let minResponseTime: TimeInterval
            public let maxResponseTime: TimeInterval
            public let percentile95: TimeInterval
            public let requestsPerSecond: Double
            public let errors: [Error]
            
            public var successRate: Double {
                return Double(successfulRequests) / Double(totalRequests)
            }
        }
        
        public func runLoadTest(
            request: URLRequest,
            configuration: LoadTestConfiguration
        ) async -> LoadTestResult {
            var responseTimes: [TimeInterval] = []
            var errors: [Error] = []
            var completedRequests = 0
            
            let startTime = Date()
            
            await withTaskGroup(of: (TimeInterval?, Error?).self) { group in
                let requestsPerWorker = configuration.numberOfRequests / configuration.concurrencyLevel
                let rampUpDelay = configuration.rampUpTime / Double(configuration.concurrencyLevel)
                
                for workerIndex in 0..<configuration.concurrencyLevel {
                    group.addTask {
                        // Ramp up delay
                        let delay = Double(workerIndex) * rampUpDelay
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        
                        var workerResponseTimes: [TimeInterval] = []
                        var workerErrors: [Error] = []
                        
                        for _ in 0..<requestsPerWorker {
                            let requestStart = Date()
                            
                            do {
                                let (_, _) = try await URLSession.shared.data(for: request)
                                let responseTime = Date().timeIntervalSince(requestStart)
                                workerResponseTimes.append(responseTime)
                            } catch {
                                workerErrors.append(error)
                            }
                        }
                        
                        return (workerResponseTimes.isEmpty ? nil : workerResponseTimes.reduce(0, +) / Double(workerResponseTimes.count), workerErrors.first)
                    }
                }
                
                for await result in group {
                    if let responseTime = result.0 {
                        responseTimes.append(responseTime)
                    }
                    
                    if let error = result.1 {
                        errors.append(error)
                    }
                    
                    completedRequests += requestsPerWorker
                }
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            let averageResponseTime = responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count)
            let minResponseTime = responseTimes.min() ?? 0
            let maxResponseTime = responseTimes.max() ?? 0
            
            let sortedTimes = responseTimes.sorted()
            let percentile95Index = Int(Double(sortedTimes.count) * 0.95)
            let percentile95 = sortedTimes.isEmpty ? 0 : sortedTimes[min(percentile95Index, sortedTimes.count - 1)]
            
            let requestsPerSecond = Double(completedRequests) / totalTime
            
            return LoadTestResult(
                totalRequests: completedRequests,
                successfulRequests: responseTimes.count,
                failedRequests: errors.count,
                averageResponseTime: averageResponseTime,
                minResponseTime: minResponseTime,
                maxResponseTime: maxResponseTime,
                percentile95: percentile95,
                requestsPerSecond: requestsPerSecond,
                errors: errors
            )
        }
    }
    
    // MARK: - Network Diagnostic Tools
    
    /// Network diagnostic utilities
    public class NetworkDiagnostics {
        
        /// Ping a host
        public static func ping(host: String, count: Int = 4) async throws -> [TimeInterval] {
            var results: [TimeInterval] = []
            
            for _ in 0..<count {
                let startTime = Date()
                
                do {
                    let url = URL(string: "https://\(host)")!
                    let (_, response) = try await URLSession.shared.data(from: url)
                    
                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        let responseTime = Date().timeIntervalSince(startTime)
                        results.append(responseTime)
                    }
                } catch {
                    // Ping failed
                }
                
                // Wait 1 second between pings
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            return results
        }
        
        /// Trace route to host
        public static func traceroute(host: String) async throws -> [String] {
            // Simplified traceroute implementation
            var route: [String] = []
            
            // This would need platform-specific implementation
            // For now, just return the target host
            route.append(host)
            
            return route
        }
        
        /// DNS lookup
        public static func dnsLookup(hostname: String) async throws -> [String] {
            return try await withCheckedThrowingContinuation { continuation in
                let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
                
                var result: DarwinBoolean = false
                let addresses = CFHostGetAddressing(host, &result)
                
                guard result.boolValue,
                      let addressArray = addresses?.takeUnretainedValue() as? [Data] else {
                    continuation.resume(throwing: NetworkError.dnsLookupFailed)
                    return
                }
                
                var ipAddresses: [String] = []
                
                for addressData in addressArray {
                    addressData.withUnsafeBytes { bytes in
                        let sockaddr = bytes.bindMemory(to: sockaddr.self).baseAddress!
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        
                        if getnameinfo(sockaddr, socklen_t(addressData.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            ipAddresses.append(String(cString: hostname))
                        }
                    }
                }
                
                continuation.resume(returning: ipAddresses)
            }
        }
        
        /// Check port connectivity
        public static func checkPort(host: String, port: Int, timeout: TimeInterval = 5) async -> Bool {
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port))
            )
            
            let connection = NWConnection(to: endpoint, using: .tcp)
            
            return await withCheckedContinuation { continuation in
                var resumed = false
                
                connection.stateUpdateHandler = { state in
                    guard !resumed else { return }
                    
                    switch state {
                    case .ready:
                        resumed = true
                        continuation.resume(returning: true)
                        connection.cancel()
                        
                    case .failed:
                        resumed = true
                        continuation.resume(returning: false)
                        
                    default:
                        break
                    }
                }
                
                connection.start(queue: .global())
                
                // Timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: false)
                    connection.cancel()
                }
            }
        }
    }
}