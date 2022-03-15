import Foundation
import os.log

/// GraphQL client for type-safe GraphQL operations
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor GraphQLClient {
    
    // MARK: - Properties
    
    /// GraphQL endpoint URL
    private let endpoint: URL
    
    /// HTTP headers
    private var headers: [String: String]
    
    /// URL session
    private let session: URLSession
    
    /// JSON encoder
    private let encoder: JSONEncoder
    
    /// JSON decoder  
    private let decoder: JSONDecoder
    
    /// Request timeout
    private let timeout: TimeInterval
    
    /// Logger
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "GraphQL")
    
    /// Query cache
    private var queryCache: [String: (data: Data, timestamp: Date)] = [:]
    
    /// Cache duration
    private let cacheDuration: TimeInterval
    
    /// Maximum cache size
    private let maxCacheSize: Int
    
    /// Subscription handlers
    private var subscriptionHandlers: [String: (Any) -> Void] = [:]
    
    /// WebSocket client for subscriptions
    private var webSocketClient: WebSocketClient?
    
    // MARK: - Initialization
    
    public init(
        endpoint: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30,
        cacheDuration: TimeInterval = 300,
        maxCacheSize: Int = 100,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.timeout = timeout
        self.cacheDuration = cacheDuration
        self.maxCacheSize = maxCacheSize
        self.session = session
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    /// Execute a GraphQL query
    public func query<T: Decodable>(
        _ query: String,
        variables: [String: Any]? = nil,
        operationName: String? = nil,
        cachePolicy: CachePolicy = .returnCacheDataElseLoad,
        as type: T.Type = T.self
    ) async throws -> T {
        // Check cache first if applicable
        if cachePolicy != .reloadIgnoringCacheData {
            let cacheKey = getCacheKey(query: query, variables: variables)
            if let cached = getCachedData(for: cacheKey),
               cachePolicy == .returnCacheDataDontLoad {
                return try decoder.decode(T.self, from: cached)
            }
        }
        
        // Build request
        let request = try buildRequest(
            query: query,
            variables: variables,
            operationName: operationName
        )
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        try validateResponse(response, data: data)
        
        // Parse GraphQL response
        let graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        
        // Check for GraphQL errors
        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw NetworkError.graphQLError(errors: errors)
        }
        
        guard let result = graphQLResponse.data else {
            throw NetworkError.noData
        }
        
        // Cache the result if applicable
        if cachePolicy != .reloadIgnoringCacheData {
            let cacheKey = getCacheKey(query: query, variables: variables)
            let resultData = try encoder.encode(result)
            cacheData(resultData, for: cacheKey)
        }
        
        logger.debug("GraphQL query executed successfully")
        return result
    }
    
    /// Execute a GraphQL mutation
    public func mutate<T: Decodable>(
        _ mutation: String,
        variables: [String: Any]? = nil,
        operationName: String? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        // Build request
        let request = try buildRequest(
            query: mutation,
            variables: variables,
            operationName: operationName
        )
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        try validateResponse(response, data: data)
        
        // Parse GraphQL response
        let graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        
        // Check for GraphQL errors
        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw NetworkError.graphQLError(errors: errors)
        }
        
        guard let result = graphQLResponse.data else {
            throw NetworkError.noData
        }
        
        logger.debug("GraphQL mutation executed successfully")
        return result
    }
    
    /// Subscribe to GraphQL subscription
    public func subscribe<T: Decodable>(
        _ subscription: String,
        variables: [String: Any]? = nil,
        operationName: String? = nil,
        as type: T.Type = T.self,
        handler: @escaping (T) -> Void
    ) async throws {
        // Initialize WebSocket if not already done
        if webSocketClient == nil {
            let wsURL = endpoint.absoluteString
                .replacingOccurrences(of: "http://", with: "ws://")
                .replacingOccurrences(of: "https://", with: "wss://")
            
            guard let url = URL(string: wsURL) else {
                throw NetworkError.invalidURL(wsURL)
            }
            
            webSocketClient = WebSocketClient(
                url: url,
                headers: headers
            )
            
            try await webSocketClient?.connect()
            setupWebSocketHandlers()
        }
        
        // Build subscription message
        let subscriptionId = UUID().uuidString
        let message = GraphQLSubscriptionMessage(
            id: subscriptionId,
            type: "start",
            payload: GraphQLRequest(
                query: subscription,
                variables: variables,
                operationName: operationName
            )
        )
        
        // Register handler
        subscriptionHandlers[subscriptionId] = { data in
            if let typedData = data as? T {
                handler(typedData)
            }
        }
        
        // Send subscription
        let messageData = try encoder.encode(message)
        try await webSocketClient?.send(data: messageData)
        
        logger.debug("GraphQL subscription started: \(subscriptionId)")
    }
    
    /// Unsubscribe from a subscription
    public func unsubscribe(id: String) async throws {
        guard let webSocketClient = webSocketClient else {
            return
        }
        
        // Remove handler
        subscriptionHandlers.removeValue(forKey: id)
        
        // Send unsubscribe message
        let message = GraphQLSubscriptionMessage(
            id: id,
            type: "stop",
            payload: nil
        )
        
        let messageData = try encoder.encode(message)
        try await webSocketClient.send(data: messageData)
        
        logger.debug("GraphQL subscription stopped: \(id)")
    }
    
    /// Execute batch queries
    public func batch<T: Decodable>(
        queries: [(query: String, variables: [String: Any]?)],
        as type: T.Type = T.self
    ) async throws -> [T] {
        var results: [T] = []
        
        // Execute queries in parallel
        try await withThrowingTaskGroup(of: T.self) { group in
            for (query, variables) in queries {
                group.addTask {
                    try await self.query(
                        query,
                        variables: variables,
                        cachePolicy: .returnCacheDataElseLoad,
                        as: T.self
                    )
                }
            }
            
            for try await result in group {
                results.append(result)
            }
        }
        
        return results
    }
    
    /// Update headers
    public func updateHeaders(_ headers: [String: String]) {
        self.headers = headers
    }
    
    /// Clear cache
    public func clearCache() {
        queryCache.removeAll()
        logger.info("GraphQL cache cleared")
    }
    
    /// Get cache size
    public func getCacheSize() -> Int {
        return queryCache.count
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        query: String,
        variables: [String: Any]?,
        operationName: String?
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // Set headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Build body
        let graphQLRequest = GraphQLRequest(
            query: query,
            variables: variables,
            operationName: operationName
        )
        
        request.httpBody = try encoder.encode(graphQLRequest)
        
        return request
    }
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: data)
        }
    }
    
    private func getCacheKey(query: String, variables: [String: Any]?) -> String {
        var key = query
        if let variables = variables {
            key += "-" + String(describing: variables)
        }
        return key.data(using: .utf8)?.base64EncodedString() ?? key
    }
    
    private func getCachedData(for key: String) -> Data? {
        guard let cached = queryCache[key] else {
            return nil
        }
        
        // Check if cache is still valid
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > cacheDuration {
            queryCache.removeValue(forKey: key)
            return nil
        }
        
        return cached.data
    }
    
    private func cacheData(_ data: Data, for key: String) {
        // Check cache size limit
        if queryCache.count >= maxCacheSize {
            // Remove oldest entry
            if let oldestKey = queryCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                queryCache.removeValue(forKey: oldestKey)
            }
        }
        
        queryCache[key] = (data: data, timestamp: Date())
    }
    
    private func setupWebSocketHandlers() {
        webSocketClient?.onMessage { [weak self] message in
            guard let self = self else { return }
            
            Task {
                await self.handleWebSocketMessage(message)
            }
        }
        
        webSocketClient?.onError { [weak self] error in
            self?.logger.error("WebSocket error: \(error)")
        }
    }
    
    private func handleWebSocketMessage(_ message: WebSocketMessage) async {
        guard let data = message.text?.data(using: .utf8) else {
            return
        }
        
        do {
            let subscriptionMessage = try decoder.decode(GraphQLSubscriptionResponse.self, from: data)
            
            switch subscriptionMessage.type {
            case "data":
                if let id = subscriptionMessage.id,
                   let handler = subscriptionHandlers[id],
                   let payload = subscriptionMessage.payload {
                    handler(payload)
                }
                
            case "error":
                if let errors = subscriptionMessage.payload as? [GraphQLError] {
                    logger.error("GraphQL subscription error: \(errors)")
                }
                
            case "complete":
                if let id = subscriptionMessage.id {
                    subscriptionHandlers.removeValue(forKey: id)
                    logger.debug("GraphQL subscription completed: \(id)")
                }
                
            default:
                break
            }
        } catch {
            logger.error("Failed to parse WebSocket message: \(error)")
        }
    }
}

// MARK: - GraphQL Types

/// GraphQL request structure
public struct GraphQLRequest: Encodable {
    public let query: String
    public let variables: [String: Any]?
    public let operationName: String?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encodeIfPresent(operationName, forKey: .operationName)
        
        if let variables = variables {
            let jsonData = try JSONSerialization.data(withJSONObject: variables)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            try container.encode(AnyEncodable(jsonObject), forKey: .variables)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case query
        case variables
        case operationName
    }
}

/// GraphQL response structure
public struct GraphQLResponse<T: Decodable>: Decodable {
    public let data: T?
    public let errors: [GraphQLError]?
    public let extensions: [String: AnyDecodable]?
}

/// GraphQL subscription message
struct GraphQLSubscriptionMessage: Codable {
    let id: String
    let type: String
    let payload: GraphQLRequest?
}

/// GraphQL subscription response
struct GraphQLSubscriptionResponse: Decodable {
    let id: String?
    let type: String
    let payload: Any?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        
        if let payloadData = try? container.decode(Data.self, forKey: .payload) {
            payload = try? JSONSerialization.jsonObject(with: payloadData)
        } else {
            payload = nil
        }
    }
}

// MARK: - Helper Types

struct AnyEncodable: Encodable {
    private let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyEncodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyEncodable.init))
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cannot encode value"
                )
            )
        }
    }
}

struct AnyDecodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyDecodable].self) {
            value = dictionary.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }
}