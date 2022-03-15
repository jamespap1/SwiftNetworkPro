import Foundation
import Network
import os.log

/// HTTP/2 client implementation with server push support
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor HTTP2Client {
    
    // MARK: - Types
    
    /// HTTP/2 stream
    public struct Stream {
        public let id: UInt32
        public let request: URLRequest
        public let priority: Priority
        public let state: State
        public let headers: [String: String]
        public let body: Data?
        
        public enum State {
            case idle
            case reservedLocal
            case reservedRemote
            case open
            case halfClosedLocal
            case halfClosedRemote
            case closed
        }
        
        public enum Priority: Int {
            case lowest = 0
            case low = 64
            case normal = 128
            case high = 192
            case highest = 255
        }
    }
    
    /// HTTP/2 frame types
    public enum FrameType: UInt8 {
        case data = 0x0
        case headers = 0x1
        case priority = 0x2
        case rstStream = 0x3
        case settings = 0x4
        case pushPromise = 0x5
        case ping = 0x6
        case goaway = 0x7
        case windowUpdate = 0x8
        case continuation = 0x9
        
        public var name: String {
            switch self {
            case .data: return "DATA"
            case .headers: return "HEADERS"
            case .priority: return "PRIORITY"
            case .rstStream: return "RST_STREAM"
            case .settings: return "SETTINGS"
            case .pushPromise: return "PUSH_PROMISE"
            case .ping: return "PING"
            case .goaway: return "GOAWAY"
            case .windowUpdate: return "WINDOW_UPDATE"
            case .continuation: return "CONTINUATION"
            }
        }
    }
    
    /// HTTP/2 frame
    public struct Frame {
        public let length: UInt32
        public let type: FrameType
        public let flags: UInt8
        public let streamId: UInt32
        public let payload: Data
        
        public init(type: FrameType, flags: UInt8 = 0, streamId: UInt32 = 0, payload: Data = Data()) {
            self.length = UInt32(payload.count)
            self.type = type
            self.flags = flags
            self.streamId = streamId
            self.payload = payload
        }
        
        public var data: Data {
            var frameData = Data()
            
            // Length (24 bits)
            frameData.append(contentsOf: [
                UInt8((length >> 16) & 0xFF),
                UInt8((length >> 8) & 0xFF),
                UInt8(length & 0xFF)
            ])
            
            // Type (8 bits)
            frameData.append(type.rawValue)
            
            // Flags (8 bits)
            frameData.append(flags)
            
            // Stream ID (31 bits + R bit)
            let streamIdBytes: [UInt8] = [
                UInt8((streamId >> 24) & 0x7F), // Clear R bit
                UInt8((streamId >> 16) & 0xFF),
                UInt8((streamId >> 8) & 0xFF),
                UInt8(streamId & 0xFF)
            ]
            frameData.append(contentsOf: streamIdBytes)
            
            // Payload
            frameData.append(payload)
            
            return frameData
        }
        
        public static func parse(from data: Data) throws -> Frame {
            guard data.count >= 9 else {
                throw NetworkError.invalidData("Insufficient data for HTTP/2 frame header")
            }
            
            let length = (UInt32(data[0]) << 16) | (UInt32(data[1]) << 8) | UInt32(data[2])
            
            guard let frameType = FrameType(rawValue: data[3]) else {
                throw NetworkError.invalidData("Unknown frame type: \(data[3])")
            }
            
            let flags = data[4]
            
            let streamId = (UInt32(data[5] & 0x7F) << 24) | 
                          (UInt32(data[6]) << 16) | 
                          (UInt32(data[7]) << 8) | 
                          UInt32(data[8])
            
            let payload = data.count > 9 ? data.subdata(in: 9..<min(Int(9 + length), data.count)) : Data()
            
            return Frame(type: frameType, flags: flags, streamId: streamId, payload: payload)
        }
    }
    
    /// HTTP/2 settings
    public struct Settings {
        public var headerTableSize: UInt32 = 4096
        public var enablePush: Bool = true
        public var maxConcurrentStreams: UInt32 = 100
        public var initialWindowSize: UInt32 = 65535
        public var maxFrameSize: UInt32 = 16384
        public var maxHeaderListSize: UInt32 = 8192
        
        public enum SettingId: UInt16 {
            case headerTableSize = 0x1
            case enablePush = 0x2
            case maxConcurrentStreams = 0x3
            case initialWindowSize = 0x4
            case maxFrameSize = 0x5
            case maxHeaderListSize = 0x6
        }
        
        public var framePayload: Data {
            var data = Data()
            
            // Header table size
            data.append(contentsOf: SettingId.headerTableSize.rawValue.bigEndianBytes)
            data.append(contentsOf: headerTableSize.bigEndianBytes)
            
            // Enable push
            data.append(contentsOf: SettingId.enablePush.rawValue.bigEndianBytes)
            data.append(contentsOf: (enablePush ? 1 : 0 as UInt32).bigEndianBytes)
            
            // Max concurrent streams
            data.append(contentsOf: SettingId.maxConcurrentStreams.rawValue.bigEndianBytes)
            data.append(contentsOf: maxConcurrentStreams.bigEndianBytes)
            
            // Initial window size
            data.append(contentsOf: SettingId.initialWindowSize.rawValue.bigEndianBytes)
            data.append(contentsOf: initialWindowSize.bigEndianBytes)
            
            // Max frame size
            data.append(contentsOf: SettingId.maxFrameSize.rawValue.bigEndianBytes)
            data.append(contentsOf: maxFrameSize.bigEndianBytes)
            
            // Max header list size
            data.append(contentsOf: SettingId.maxHeaderListSize.rawValue.bigEndianBytes)
            data.append(contentsOf: maxHeaderListSize.bigEndianBytes)
            
            return data
        }
    }
    
    /// HTTP/2 connection state
    public enum ConnectionState {
        case idle
        case connecting
        case connected
        case goingAway
        case closed
    }
    
    /// Server push handler
    public typealias PushPromiseHandler = (URLRequest, @escaping (Bool) -> Void) -> Void
    
    // MARK: - Properties
    
    private let host: String
    private let port: Int
    private let useTLS: Bool
    private var connection: NWConnection?
    private var state: ConnectionState = .idle
    private var settings = Settings()
    private var remoteSettings = Settings()
    private var streams: [UInt32: Stream] = [:]
    private var nextStreamId: UInt32 = 1
    private var connectionWindowSize: Int32 = 65535
    private var frameBuffer = Data()
    
    private var pushPromiseHandler: PushPromiseHandler?
    
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "HTTP2")
    
    // MARK: - Initialization
    
    public init(host: String, port: Int = 443, useTLS: Bool = true) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }
    
    // MARK: - Public Methods
    
    /// Connect to server
    public func connect() async throws {
        guard state == .idle else { return }
        
        state = .connecting
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let parameters: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            
            // Configure ALPN for HTTP/2
            sec_protocol_options_add_tls_application_protocol(
                tlsOptions.securityProtocolOptions,
                "h2".data(using: .utf8)!.withUnsafeBytes { $0 }
            )
            
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = .tcp
        }
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection?.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleConnectionState(state, continuation: continuation)
                }
            }
            
            connection?.start(queue: .global())
        }
        
        // Send connection preface
        try await sendConnectionPreface()
        
        // Send settings
        try await sendSettings()
        
        // Start receiving frames
        receiveFrames()
        
        state = .connected
        logger.info("HTTP/2 connection established to \(host):\(port)")
    }
    
    /// Disconnect from server
    public func disconnect() {
        connection?.cancel()
        connection = nil
        state = .closed
        streams.removeAll()
        
        logger.info("HTTP/2 connection closed")
    }
    
    /// Send HTTP request
    public func sendRequest(_ request: URLRequest, priority: Stream.Priority = .normal) async throws -> (Data?, URLResponse?) {
        guard state == .connected else {
            throw NetworkError.connectionError("HTTP/2 connection not established")
        }
        
        let streamId = nextStreamId
        nextStreamId += 2 // Client streams are odd-numbered
        
        // Create stream
        let stream = Stream(
            id: streamId,
            request: request,
            priority: priority,
            state: .idle,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        )
        
        streams[streamId] = stream
        
        // Send headers frame
        try await sendHeadersFrame(for: stream)
        
        // Send data frame if body exists
        if let body = request.httpBody {
            try await sendDataFrame(streamId: streamId, data: body, endStream: true)
        }
        
        // Wait for response (simplified - in production, use proper async stream handling)
        return try await waitForResponse(streamId: streamId)
    }
    
    /// Set push promise handler
    public func onPushPromise(_ handler: @escaping PushPromiseHandler) {
        self.pushPromiseHandler = handler
    }
    
    /// Update settings
    public func updateSettings(_ newSettings: Settings) async throws {
        self.settings = newSettings
        try await sendSettings()
    }
    
    // MARK: - Private Methods
    
    private func handleConnectionState(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>?) {
        switch state {
        case .ready:
            continuation?.resume()
        case .failed(let error):
            self.state = .closed
            continuation?.resume(throwing: error)
        case .cancelled:
            self.state = .closed
        default:
            break
        }
    }
    
    private func sendConnectionPreface() async throws {
        let preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".data(using: .ascii)!
        try await send(data: preface)
        
        logger.debug("Sent HTTP/2 connection preface")
    }
    
    private func sendSettings() async throws {
        let settingsFrame = Frame(type: .settings, payload: settings.framePayload)
        try await sendFrame(settingsFrame)
        
        logger.debug("Sent SETTINGS frame")
    }
    
    private func sendHeadersFrame(for stream: Stream) async throws {
        let headers = encodeHeaders(stream.headers, method: stream.request.httpMethod ?? "GET", path: stream.request.url?.path ?? "/")
        
        let flags: UInt8 = stream.body == nil ? 0x1 : 0x4 // END_STREAM if no body, END_HEADERS
        let headersFrame = Frame(type: .headers, flags: flags, streamId: stream.id, payload: headers)
        
        try await sendFrame(headersFrame)
        
        logger.debug("Sent HEADERS frame for stream \(stream.id)")
    }
    
    private func sendDataFrame(streamId: UInt32, data: Data, endStream: Bool) async throws {
        let flags: UInt8 = endStream ? 0x1 : 0x0 // END_STREAM flag
        let dataFrame = Frame(type: .data, flags: flags, streamId: streamId, payload: data)
        
        try await sendFrame(dataFrame)
        
        logger.debug("Sent DATA frame for stream \(streamId)")
    }
    
    private func sendFrame(_ frame: Frame) async throws {
        try await send(data: frame.data)
    }
    
    private func send(data: Data) async throws {
        guard let connection = connection else {
            throw NetworkError.connectionError("Connection not established")
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receiveFrames() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task {
                if let data = data, !data.isEmpty {
                    await self?.processReceivedData(data)
                }
                
                if !isComplete && error == nil {
                    self?.receiveFrames()
                }
            }
        }
    }
    
    private func processReceivedData(_ data: Data) {
        frameBuffer.append(data)
        
        while frameBuffer.count >= 9 {
            do {
                let frame = try Frame.parse(from: frameBuffer)
                let frameSize = Int(9 + frame.length)
                
                if frameBuffer.count >= frameSize {
                    frameBuffer.removeFirst(frameSize)
                    await processFrame(frame)
                } else {
                    break // Wait for more data
                }
            } catch {
                logger.error("Failed to parse frame: \(error)")
                break
            }
        }
    }
    
    private func processFrame(_ frame: Frame) async {
        logger.debug("Received \(frame.type.name) frame (stream: \(frame.streamId))")
        
        switch frame.type {
        case .settings:
            await handleSettingsFrame(frame)
        case .headers:
            await handleHeadersFrame(frame)
        case .data:
            await handleDataFrame(frame)
        case .pushPromise:
            await handlePushPromiseFrame(frame)
        case .ping:
            await handlePingFrame(frame)
        case .windowUpdate:
            await handleWindowUpdateFrame(frame)
        case .rstStream:
            await handleRstStreamFrame(frame)
        case .goaway:
            await handleGoAwayFrame(frame)
        default:
            logger.warning("Unhandled frame type: \(frame.type.name)")
        }
    }
    
    private func handleSettingsFrame(_ frame: Frame) async {
        if frame.flags & 0x1 == 0 { // Not ACK
            // Process settings
            var offset = 0
            while offset + 6 <= frame.payload.count {
                let settingId = frame.payload.withUnsafeBytes { bytes in
                    UInt16(bigEndian: bytes.load(fromByteOffset: offset, as: UInt16.self))
                }
                let value = frame.payload.withUnsafeBytes { bytes in
                    UInt32(bigEndian: bytes.load(fromByteOffset: offset + 2, as: UInt32.self))
                }
                
                // Update remote settings
                switch Settings.SettingId(rawValue: settingId) {
                case .headerTableSize:
                    remoteSettings.headerTableSize = value
                case .enablePush:
                    remoteSettings.enablePush = value != 0
                case .maxConcurrentStreams:
                    remoteSettings.maxConcurrentStreams = value
                case .initialWindowSize:
                    remoteSettings.initialWindowSize = value
                case .maxFrameSize:
                    remoteSettings.maxFrameSize = value
                case .maxHeaderListSize:
                    remoteSettings.maxHeaderListSize = value
                case .none:
                    logger.warning("Unknown setting ID: \(settingId)")
                }
                
                offset += 6
            }
            
            // Send ACK
            let ackFrame = Frame(type: .settings, flags: 0x1) // ACK flag
            do {
                try await sendFrame(ackFrame)
            } catch {
                logger.error("Failed to send SETTINGS ACK: \(error)")
            }
        }
    }
    
    private func handleHeadersFrame(_ frame: Frame) async {
        // Simplified header handling
        logger.debug("Received headers for stream \(frame.streamId)")
    }
    
    private func handleDataFrame(_ frame: Frame) async {
        logger.debug("Received data for stream \(frame.streamId): \(frame.payload.count) bytes")
    }
    
    private func handlePushPromiseFrame(_ frame: Frame) async {
        guard remoteSettings.enablePush else {
            logger.warning("Received PUSH_PROMISE but push is disabled")
            return
        }
        
        // Extract promised stream ID
        guard frame.payload.count >= 4 else { return }
        
        let promisedStreamId = frame.payload.withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.load(fromByteOffset: 0, as: UInt32.self)) & 0x7FFFFFFF
        }
        
        logger.info("Received PUSH_PROMISE for stream \(promisedStreamId)")
        
        // Create dummy request for push promise handler
        let promisedRequest = URLRequest(url: URL(string: "https://\(host)/pushed")!)
        
        pushPromiseHandler?(promisedRequest) { accept in
            if !accept {
                // Send RST_STREAM to reject the push
                Task {
                    let rstFrame = Frame(
                        type: .rstStream,
                        streamId: promisedStreamId,
                        payload: Data([0, 0, 0, 8]) // CANCEL error code
                    )
                    try? await self.sendFrame(rstFrame)
                }
            }
        }
    }
    
    private func handlePingFrame(_ frame: Frame) async {
        if frame.flags & 0x1 == 0 { // Not ACK
            // Send PING ACK
            let pingAckFrame = Frame(type: .ping, flags: 0x1, payload: frame.payload)
            do {
                try await sendFrame(pingAckFrame)
            } catch {
                logger.error("Failed to send PING ACK: \(error)")
            }
        }
    }
    
    private func handleWindowUpdateFrame(_ frame: Frame) async {
        let windowSizeIncrement = frame.payload.withUnsafeBytes { bytes in
            Int32(bigEndian: bytes.load(fromByteOffset: 0, as: UInt32.self)) & 0x7FFFFFFF
        }
        
        if frame.streamId == 0 {
            // Connection-level window update
            connectionWindowSize += windowSizeIncrement
        }
        
        logger.debug("Window updated by \(windowSizeIncrement) for stream \(frame.streamId)")
    }
    
    private func handleRstStreamFrame(_ frame: Frame) async {
        let errorCode = frame.payload.withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.load(fromByteOffset: 0, as: UInt32.self))
        }
        
        streams.removeValue(forKey: frame.streamId)
        logger.info("Stream \(frame.streamId) reset with error code: \(errorCode)")
    }
    
    private func handleGoAwayFrame(_ frame: Frame) async {
        state = .goingAway
        
        let lastStreamId = frame.payload.withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.load(fromByteOffset: 0, as: UInt32.self)) & 0x7FFFFFFF
        }
        
        logger.info("Received GOAWAY, last stream ID: \(lastStreamId)")
    }
    
    private func encodeHeaders(_ headers: [String: String], method: String, path: String) -> Data {
        // Simplified HPACK encoding (in production, use proper HPACK implementation)
        var encoded = Data()
        
        // Pseudo-headers
        encoded.append(encodeHeader(":method", method))
        encoded.append(encodeHeader(":path", path))
        encoded.append(encodeHeader(":scheme", useTLS ? "https" : "http"))
        encoded.append(encodeHeader(":authority", host))
        
        // Regular headers
        for (name, value) in headers {
            encoded.append(encodeHeader(name.lowercased(), value))
        }
        
        return encoded
    }
    
    private func encodeHeader(_ name: String, _ value: String) -> Data {
        // Simplified literal encoding (not indexed)
        var data = Data([0x00]) // Literal header field without indexing
        
        // Name length and name
        data.append(UInt8(name.count))
        data.append(name.data(using: .utf8)!)
        
        // Value length and value
        data.append(UInt8(value.count))
        data.append(value.data(using: .utf8)!)
        
        return data
    }
    
    private func waitForResponse(streamId: UInt32) async throws -> (Data?, URLResponse?) {
        // Simplified response waiting - in production, implement proper stream state machine
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let response = HTTPURLResponse(
            url: URL(string: "https://\(host)")!,
            statusCode: 200,
            httpVersion: "HTTP/2.0",
            headerFields: nil
        )
        
        return (Data(), response)
    }
}

// MARK: - Extensions

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        return [UInt8(self >> 8), UInt8(self & 0xFF)]
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        return [
            UInt8(self >> 24),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}