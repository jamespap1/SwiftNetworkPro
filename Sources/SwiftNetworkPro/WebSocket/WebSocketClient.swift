import Foundation
import os.log

/// WebSocket client for real-time communication
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor WebSocketClient {
    
    // MARK: - Properties
    
    /// WebSocket connection state
    public enum State {
        case disconnected
        case connecting
        case connected
        case disconnecting
        
        var isConnected: Bool {
            self == .connected
        }
    }
    
    /// WebSocket close code
    public enum CloseCode: Int {
        case normalClosure = 1000
        case goingAway = 1001
        case protocolError = 1002
        case unsupportedData = 1003
        case noStatusReceived = 1005
        case abnormalClosure = 1006
        case invalidFramePayloadData = 1007
        case policyViolation = 1008
        case messageTooBig = 1009
        case mandatoryExtensionMissing = 1010
        case internalServerError = 1011
        case tlsHandshakeFailure = 1015
    }
    
    /// Current connection state
    private(set) var state: State = .disconnected
    
    /// WebSocket URL
    private let url: URL
    
    /// WebSocket task
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// URL session
    private let session: URLSession
    
    /// Message handlers
    private var messageHandlers: [(WebSocketMessage) -> Void] = []
    
    /// Connection handlers
    private var connectionHandlers: [(State) -> Void] = []
    
    /// Error handlers
    private var errorHandlers: [(Error) -> Void] = []
    
    /// Ping interval
    private var pingInterval: TimeInterval?
    
    /// Ping timer task
    private var pingTask: Task<Void, Never>?
    
    /// Auto-reconnect
    private var autoReconnect: Bool
    
    /// Reconnect delay
    private var reconnectDelay: TimeInterval
    
    /// Maximum reconnect attempts
    private var maxReconnectAttempts: Int
    
    /// Current reconnect attempt
    private var reconnectAttempt: Int = 0
    
    /// Logger
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "WebSocket")
    
    /// Message queue for offline messages
    private var messageQueue: [WebSocketMessage] = []
    
    /// Maximum message queue size
    private let maxQueueSize: Int
    
    /// Request headers
    private var headers: [String: String]
    
    /// Subprotocols
    private var subprotocols: [String]
    
    // MARK: - Initialization
    
    public init(
        url: URL,
        headers: [String: String] = [:],
        subprotocols: [String] = [],
        pingInterval: TimeInterval? = 30,
        autoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 5,
        maxReconnectAttempts: Int = 5,
        maxQueueSize: Int = 100,
        session: URLSession = .shared
    ) {
        self.url = url
        self.headers = headers
        self.subprotocols = subprotocols
        self.pingInterval = pingInterval
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.maxQueueSize = maxQueueSize
        self.session = session
    }
    
    // MARK: - Public Methods
    
    /// Connect to WebSocket server
    public func connect() async throws {
        guard state == .disconnected else {
            logger.warning("WebSocket already connected or connecting")
            return
        }
        
        state = .connecting
        notifyConnectionHandlers()
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        if !subprotocols.isEmpty {
            request.setValue(subprotocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        Task {
            await receiveMessages()
        }
        
        // Start ping if configured
        if let interval = pingInterval {
            startPing(interval: interval)
        }
        
        // Send queued messages
        await sendQueuedMessages()
        
        state = .connected
        reconnectAttempt = 0
        notifyConnectionHandlers()
        
        logger.info("WebSocket connected to \(self.url)")
    }
    
    /// Disconnect from WebSocket server
    public func disconnect(code: CloseCode = .normalClosure, reason: String? = nil) async {
        guard state == .connected || state == .connecting else {
            return
        }
        
        state = .disconnecting
        notifyConnectionHandlers()
        
        // Stop ping
        pingTask?.cancel()
        pingTask = nil
        
        // Cancel the WebSocket task
        let reasonData = reason?.data(using: .utf8)
        webSocketTask?.cancel(with: .init(rawValue: code.rawValue) ?? .normalClosure, reason: reasonData)
        webSocketTask = nil
        
        state = .disconnected
        notifyConnectionHandlers()
        
        logger.info("WebSocket disconnected")
    }
    
    /// Send text message
    public func send(text: String) async throws {
        try await send(.string(text))
    }
    
    /// Send data message
    public func send(data: Data) async throws {
        try await send(.data(data))
    }
    
    /// Send WebSocket message
    public func send(_ message: WebSocketMessage) async throws {
        guard state == .connected else {
            // Queue message if not connected
            if messageQueue.count < maxQueueSize {
                messageQueue.append(message)
                logger.info("Message queued (queue size: \(self.messageQueue.count))")
            } else {
                throw NetworkError.webSocketConnectionFailed(WebSocketError.notConnected)
            }
            return
        }
        
        let wsMessage: URLSessionWebSocketTask.Message
        switch message {
        case .string(let text):
            wsMessage = .string(text)
        case .data(let data):
            wsMessage = .data(data)
        }
        
        try await webSocketTask?.send(wsMessage)
        logger.debug("Sent message: \(message)")
    }
    
    /// Send ping
    public func ping() async throws {
        guard state == .connected else {
            throw NetworkError.webSocketConnectionFailed(WebSocketError.notConnected)
        }
        
        try await webSocketTask?.sendPing()
        logger.debug("Sent ping")
    }
    
    /// Add message handler
    public func onMessage(_ handler: @escaping (WebSocketMessage) -> Void) {
        messageHandlers.append(handler)
    }
    
    /// Add connection state handler
    public func onConnectionStateChange(_ handler: @escaping (State) -> Void) {
        connectionHandlers.append(handler)
    }
    
    /// Add error handler
    public func onError(_ handler: @escaping (Error) -> Void) {
        errorHandlers.append(handler)
    }
    
    /// Clear all handlers
    public func clearHandlers() {
        messageHandlers.removeAll()
        connectionHandlers.removeAll()
        errorHandlers.removeAll()
    }
    
    /// Get current state
    public func getState() -> State {
        return state
    }
    
    /// Check if connected
    public func isConnected() -> Bool {
        return state.isConnected
    }
    
    // MARK: - Private Methods
    
    private func receiveMessages() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            while state == .connected || state == .connecting {
                let message = try await webSocketTask.receive()
                
                let wsMessage: WebSocketMessage
                switch message {
                case .string(let text):
                    wsMessage = .string(text)
                case .data(let data):
                    wsMessage = .data(data)
                @unknown default:
                    logger.warning("Received unknown message type")
                    continue
                }
                
                notifyMessageHandlers(wsMessage)
                logger.debug("Received message: \(wsMessage)")
            }
        } catch {
            if state == .connected || state == .connecting {
                logger.error("WebSocket receive error: \(error)")
                notifyErrorHandlers(error)
                
                // Attempt reconnection if configured
                if autoReconnect && reconnectAttempt < maxReconnectAttempts {
                    await attemptReconnection()
                } else {
                    state = .disconnected
                    notifyConnectionHandlers()
                }
            }
        }
    }
    
    private func startPing(interval: TimeInterval) {
        pingTask = Task {
            while !Task.isCancelled && state == .connected {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                if state == .connected {
                    do {
                        try await ping()
                    } catch {
                        logger.error("Ping failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func attemptReconnection() async {
        reconnectAttempt += 1
        logger.info("Attempting reconnection (\(self.reconnectAttempt)/\(self.maxReconnectAttempts))...")
        
        state = .disconnected
        notifyConnectionHandlers()
        
        // Wait before reconnecting
        try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
        
        do {
            try await connect()
        } catch {
            logger.error("Reconnection failed: \(error)")
            
            if reconnectAttempt < maxReconnectAttempts {
                await attemptReconnection()
            } else {
                logger.error("Maximum reconnection attempts reached")
                state = .disconnected
                notifyConnectionHandlers()
            }
        }
    }
    
    private func sendQueuedMessages() async {
        guard !messageQueue.isEmpty else { return }
        
        logger.info("Sending \(self.messageQueue.count) queued messages...")
        
        for message in messageQueue {
            do {
                try await send(message)
            } catch {
                logger.error("Failed to send queued message: \(error)")
            }
        }
        
        messageQueue.removeAll()
    }
    
    private func notifyMessageHandlers(_ message: WebSocketMessage) {
        messageHandlers.forEach { handler in
            handler(message)
        }
    }
    
    private func notifyConnectionHandlers() {
        let currentState = state
        connectionHandlers.forEach { handler in
            handler(currentState)
        }
    }
    
    private func notifyErrorHandlers(_ error: Error) {
        errorHandlers.forEach { handler in
            handler(error)
        }
    }
}

// MARK: - WebSocket Message

public enum WebSocketMessage: Equatable {
    case string(String)
    case data(Data)
    
    public var text: String? {
        switch self {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8)
        }
    }
    
    public var data: Data {
        switch self {
        case .string(let text):
            return text.data(using: .utf8) ?? Data()
        case .data(let data):
            return data
        }
    }
}

// MARK: - WebSocket Error

public enum WebSocketError: LocalizedError {
    case notConnected
    case connectionFailed(Error?)
    case invalidURL
    case invalidMessage
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected"
        case .connectionFailed(let error):
            return "WebSocket connection failed: \(error?.localizedDescription ?? "Unknown error")"
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .invalidMessage:
            return "Invalid WebSocket message"
        case .timeout:
            return "WebSocket operation timed out"
        }
    }
}

// MARK: - WebSocket Configuration

public struct WebSocketConfiguration {
    public var url: URL
    public var headers: [String: String]
    public var subprotocols: [String]
    public var pingInterval: TimeInterval?
    public var autoReconnect: Bool
    public var reconnectDelay: TimeInterval
    public var maxReconnectAttempts: Int
    public var maxQueueSize: Int
    public var compressionEnabled: Bool
    public var timeout: TimeInterval
    
    public init(
        url: URL,
        headers: [String: String] = [:],
        subprotocols: [String] = [],
        pingInterval: TimeInterval? = 30,
        autoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 5,
        maxReconnectAttempts: Int = 5,
        maxQueueSize: Int = 100,
        compressionEnabled: Bool = true,
        timeout: TimeInterval = 60
    ) {
        self.url = url
        self.headers = headers
        self.subprotocols = subprotocols
        self.pingInterval = pingInterval
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.maxQueueSize = maxQueueSize
        self.compressionEnabled = compressionEnabled
        self.timeout = timeout
    }
}