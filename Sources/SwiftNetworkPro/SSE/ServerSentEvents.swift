import Foundation
import os.log
import Combine

/// Server-Sent Events (SSE) client
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor ServerSentEventsClient {
    
    // MARK: - Types
    
    /// SSE event
    public struct Event {
        public let id: String?
        public let event: String?
        public let data: String
        public let retry: Int?
        public let timestamp: Date
        
        public init(
            id: String? = nil,
            event: String? = nil,
            data: String,
            retry: Int? = nil,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.event = event
            self.data = data
            self.retry = retry
            self.timestamp = timestamp
        }
    }
    
    /// SSE state
    public enum State {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(Error)
        
        public var isActive: Bool {
            switch self {
            case .connected, .connecting, .reconnecting:
                return true
            default:
                return false
            }
        }
    }
    
    /// SSE configuration
    public struct Configuration {
        public let reconnectTime: TimeInterval
        public let maxReconnectTime: TimeInterval
        public let reconnectBackoff: Double
        public let maxReconnectAttempts: Int
        public let timeout: TimeInterval
        public let bufferSize: Int
        public let keepAliveInterval: TimeInterval?
        
        public init(
            reconnectTime: TimeInterval = 3,
            maxReconnectTime: TimeInterval = 30,
            reconnectBackoff: Double = 1.5,
            maxReconnectAttempts: Int = -1, // -1 = unlimited
            timeout: TimeInterval = 300,
            bufferSize: Int = 8192,
            keepAliveInterval: TimeInterval? = 30
        ) {
            self.reconnectTime = reconnectTime
            self.maxReconnectTime = maxReconnectTime
            self.reconnectBackoff = reconnectBackoff
            self.maxReconnectAttempts = maxReconnectAttempts
            self.timeout = timeout
            self.bufferSize = bufferSize
            self.keepAliveInterval = keepAliveInterval
        }
        
        public static let `default` = Configuration()
    }
    
    /// SSE error
    public enum SSEError: LocalizedError {
        case invalidURL
        case connectionFailed(Error)
        case invalidResponse
        case streamEnded
        case reconnectLimitReached
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .connectionFailed(let error):
                return "Connection failed: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server"
            case .streamEnded:
                return "Stream ended unexpectedly"
            case .reconnectLimitReached:
                return "Maximum reconnection attempts reached"
            }
        }
    }
    
    // MARK: - Properties
    
    private let url: URL
    private let configuration: Configuration
    private var headers: [String: String]
    private var state: State = .disconnected
    private var session: URLSession!
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private var lastEventId: String?
    private var reconnectTime: TimeInterval
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private var keepAliveTimer: Timer?
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "SSE")
    
    // Handlers
    private var eventHandler: ((Event) -> Void)?
    private var stateHandler: ((State) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    
    // Event subject for Combine
    private let eventSubject = PassthroughSubject<Event, Never>()
    public var eventPublisher: AnyPublisher<Event, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    public init(
        url: URL,
        configuration: Configuration = .default,
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.configuration = configuration
        self.headers = headers
        self.reconnectTime = configuration.reconnectTime
        
        setupSession()
    }
    
    deinit {
        disconnect()
    }
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }
    
    // MARK: - Public Methods
    
    /// Connect to SSE endpoint
    public func connect() async throws {
        guard state != .connected && state != .connecting else { return }
        
        setState(.connecting)
        
        do {
            try await startConnection()
        } catch {
            setState(.failed(error))
            throw error
        }
    }
    
    /// Disconnect from SSE endpoint
    public func disconnect() {
        dataTask?.cancel()
        dataTask = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        
        buffer.removeAll()
        setState(.disconnected)
        
        logger.info("Disconnected from SSE")
    }
    
    /// Get current state
    public func getState() -> State {
        return state
    }
    
    /// Set event handler
    public func onEvent(_ handler: @escaping (Event) -> Void) {
        self.eventHandler = handler
    }
    
    /// Set state change handler
    public func onStateChange(_ handler: @escaping (State) -> Void) {
        self.stateHandler = handler
    }
    
    /// Set error handler
    public func onError(_ handler: @escaping (Error) -> Void) {
        self.errorHandler = handler
    }
    
    /// Send custom header
    public func setHeader(_ value: String, for field: String) {
        headers[field] = value
    }
    
    /// Remove header
    public func removeHeader(_ field: String) {
        headers.removeValue(forKey: field)
    }
    
    // MARK: - Private Methods
    
    private func startConnection() async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Add last event ID if available
        if let lastEventId = lastEventId {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }
        
        // Add custom headers
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Start data task
        dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            Task {
                await self?.handleResponse(data: data, response: response, error: error)
            }
        }
        
        dataTask?.resume()
        
        // Start keep-alive timer if configured
        if let keepAliveInterval = configuration.keepAliveInterval {
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { _ in
                // Keep connection alive
                self.logger.debug("Keep-alive ping")
            }
        }
        
        logger.info("Connected to SSE: \(url)")
    }
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            logger.error("SSE connection error: \(error)")
            handleConnectionError(error)
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            handleConnectionError(SSEError.invalidResponse)
            return
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let error = NetworkError.invalidStatusCode(httpResponse.statusCode, data: data)
            handleConnectionError(error)
            return
        }
        
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("text/event-stream") else {
            handleConnectionError(SSEError.invalidResponse)
            return
        }
        
        setState(.connected)
        reconnectAttempts = 0
        reconnectTime = configuration.reconnectTime
        
        if let data = data {
            processData(data)
        }
        
        // Continue receiving data
        receiveData()
    }
    
    private func receiveData() {
        dataTask?.delegate = StreamDelegate { [weak self] data in
            Task {
                await self?.processData(data)
            }
        }
    }
    
    private func processData(_ data: Data) {
        buffer.append(data)
        
        // Process buffer line by line
        while let lineRange = buffer.range(of: "\n".data(using: .utf8)!) {
            let lineData = buffer[..<lineRange.lowerBound]
            buffer.removeSubrange(..<lineRange.upperBound)
            
            if let line = String(data: lineData, encoding: .utf8) {
                processLine(line)
            }
        }
        
        // Check buffer size limit
        if buffer.count > configuration.bufferSize {
            logger.warning("Buffer size exceeded, clearing buffer")
            buffer.removeAll()
        }
    }
    
    private func processLine(_ line: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty line indicates end of event
        if trimmedLine.isEmpty {
            flushEvent()
            return
        }
        
        // Comment line
        if trimmedLine.hasPrefix(":") {
            // Ignore comments
            return
        }
        
        // Parse field and value
        let components = trimmedLine.split(separator: ":", maxSplits: 1)
        guard !components.isEmpty else { return }
        
        let field = String(components[0]).trimmingCharacters(in: .whitespaces)
        let value = components.count > 1 ? 
            String(components[1]).trimmingCharacters(in: .whitespaces) : ""
        
        processField(field: field, value: value)
    }
    
    private var currentEventId: String?
    private var currentEventType: String?
    private var currentEventData = ""
    private var currentRetry: Int?
    
    private func processField(field: String, value: String) {
        switch field {
        case "id":
            currentEventId = value
            lastEventId = value
            
        case "event":
            currentEventType = value
            
        case "data":
            if !currentEventData.isEmpty {
                currentEventData += "\n"
            }
            currentEventData += value
            
        case "retry":
            if let retry = Int(value) {
                currentRetry = retry
                reconnectTime = TimeInterval(retry) / 1000.0
            }
            
        default:
            // Unknown field, ignore
            break
        }
    }
    
    private func flushEvent() {
        guard !currentEventData.isEmpty else { return }
        
        let event = Event(
            id: currentEventId,
            event: currentEventType,
            data: currentEventData,
            retry: currentRetry
        )
        
        // Dispatch event
        eventHandler?(event)
        eventSubject.send(event)
        
        logger.debug("Received SSE event: \(currentEventType ?? "message")")
        
        // Reset current event
        currentEventId = nil
        currentEventType = nil
        currentEventData = ""
        currentRetry = nil
    }
    
    private func handleConnectionError(_ error: Error) {
        logger.error("SSE connection error: \(error)")
        
        errorHandler?(error)
        
        // Check if we should reconnect
        if configuration.maxReconnectAttempts < 0 || 
           reconnectAttempts < configuration.maxReconnectAttempts {
            scheduleReconnect()
        } else {
            setState(.failed(SSEError.reconnectLimitReached))
        }
    }
    
    private func scheduleReconnect() {
        setState(.reconnecting)
        reconnectAttempts += 1
        
        logger.info("Scheduling reconnect #\(reconnectAttempts) in \(reconnectTime)s")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectTime, repeats: false) { _ in
            Task {
                try? await self.connect()
            }
        }
        
        // Apply backoff
        reconnectTime = min(reconnectTime * configuration.reconnectBackoff, configuration.maxReconnectTime)
    }
    
    private func setState(_ newState: State) {
        state = newState
        stateHandler?(newState)
        
        logger.debug("SSE state changed: \(String(describing: newState))")
    }
}

// MARK: - Stream Delegate

private class StreamDelegate: NSObject, URLSessionDataDelegate {
    private let dataHandler: (Data) -> Void
    
    init(dataHandler: @escaping (Data) -> Void) {
        self.dataHandler = dataHandler
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataHandler(data)
    }
}

// MARK: - Event Stream Parser

/// SSE event stream parser
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class EventStreamParser {
    
    private var buffer = ""
    private var currentEvent = ServerSentEventsClient.Event(data: "")
    private let eventHandler: (ServerSentEventsClient.Event) -> Void
    
    public init(eventHandler: @escaping (ServerSentEventsClient.Event) -> Void) {
        self.eventHandler = eventHandler
    }
    
    public func parse(_ text: String) {
        buffer += text
        
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(..<newlineRange.upperBound)
            
            processLine(line)
        }
    }
    
    private func processLine(_ line: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedLine.isEmpty {
            if !currentEvent.data.isEmpty {
                eventHandler(currentEvent)
                currentEvent = ServerSentEventsClient.Event(data: "")
            }
            return
        }
        
        if trimmedLine.hasPrefix(":") {
            return // Comment
        }
        
        if let colonIndex = trimmedLine.firstIndex(of: ":") {
            let field = String(trimmedLine[..<colonIndex])
            var value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
            
            if value.hasPrefix(" ") {
                value = String(value.dropFirst())
            }
            
            switch field {
            case "id":
                currentEvent = ServerSentEventsClient.Event(
                    id: value,
                    event: currentEvent.event,
                    data: currentEvent.data,
                    retry: currentEvent.retry
                )
            case "event":
                currentEvent = ServerSentEventsClient.Event(
                    id: currentEvent.id,
                    event: value,
                    data: currentEvent.data,
                    retry: currentEvent.retry
                )
            case "data":
                let newData = currentEvent.data.isEmpty ? value : currentEvent.data + "\n" + value
                currentEvent = ServerSentEventsClient.Event(
                    id: currentEvent.id,
                    event: currentEvent.event,
                    data: newData,
                    retry: currentEvent.retry
                )
            case "retry":
                if let retryValue = Int(value) {
                    currentEvent = ServerSentEventsClient.Event(
                        id: currentEvent.id,
                        event: currentEvent.event,
                        data: currentEvent.data,
                        retry: retryValue
                    )
                }
            default:
                break
            }
        }
    }
}