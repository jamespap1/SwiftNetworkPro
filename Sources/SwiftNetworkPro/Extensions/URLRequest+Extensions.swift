import Foundation
import CryptoKit

/// URLRequest extensions for SwiftNetworkPro
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public extension URLRequest {
    
    // MARK: - Builder Pattern
    
    /// Create URLRequest with builder pattern
    static func builder(url: URL) -> URLRequestBuilder {
        return URLRequestBuilder(url: url)
    }
    
    /// Create URLRequest from string URL
    static func builder(urlString: String) throws -> URLRequestBuilder {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        return URLRequestBuilder(url: url)
    }
    
    // MARK: - HTTP Methods
    
    /// Set HTTP method
    mutating func setMethod(_ method: HTTPMethod) {
        self.httpMethod = method.rawValue
    }
    
    /// Get HTTP method as enum
    var method: HTTPMethod? {
        guard let httpMethod = httpMethod else { return nil }
        return HTTPMethod(rawValue: httpMethod)
    }
    
    // MARK: - Headers
    
    /// Set header value
    mutating func setHeader(_ value: String, for field: String) {
        setValue(value, forHTTPHeaderField: field)
    }
    
    /// Set multiple headers
    mutating func setHeaders(_ headers: [String: String]) {
        headers.forEach { setHeader($0.value, for: $0.key) }
    }
    
    /// Add header if not exists
    mutating func addHeaderIfMissing(_ value: String, for field: String) {
        if self.value(forHTTPHeaderField: field) == nil {
            setHeader(value, for: field)
        }
    }
    
    /// Get all headers
    var headers: [String: String] {
        return allHTTPHeaderFields ?? [:]
    }
    
    /// Check if has header
    func hasHeader(_ field: String) -> Bool {
        return value(forHTTPHeaderField: field) != nil
    }
    
    // MARK: - Content Type
    
    /// Set content type
    mutating func setContentType(_ contentType: ContentType) {
        setHeader(contentType.rawValue, for: "Content-Type")
    }
    
    /// Get content type
    var contentType: ContentType? {
        guard let value = value(forHTTPHeaderField: "Content-Type") else { return nil }
        return ContentType(rawValue: value)
    }
    
    /// Common content types
    enum ContentType: String {
        case json = "application/json"
        case xml = "application/xml"
        case formUrlEncoded = "application/x-www-form-urlencoded"
        case multipartFormData = "multipart/form-data"
        case plainText = "text/plain"
        case html = "text/html"
        case octetStream = "application/octet-stream"
        case pdf = "application/pdf"
        case zip = "application/zip"
    }
    
    // MARK: - Accept
    
    /// Set accept header
    mutating func setAccept(_ contentType: ContentType) {
        setHeader(contentType.rawValue, for: "Accept")
    }
    
    /// Set multiple accept types
    mutating func setAccept(_ contentTypes: [ContentType]) {
        let acceptValue = contentTypes.map { $0.rawValue }.joined(separator: ", ")
        setHeader(acceptValue, for: "Accept")
    }
    
    // MARK: - Authorization
    
    /// Set basic authorization
    mutating func setBasicAuth(username: String, password: String) {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return }
        let base64 = data.base64EncodedString()
        setHeader("Basic \(base64)", for: "Authorization")
    }
    
    /// Set bearer token
    mutating func setBearerToken(_ token: String) {
        setHeader("Bearer \(token)", for: "Authorization")
    }
    
    /// Set API key
    mutating func setAPIKey(_ key: String, header: String = "X-API-Key") {
        setHeader(key, for: header)
    }
    
    // MARK: - Body
    
    /// Set JSON body
    mutating func setJSONBody<T: Encodable>(_ object: T, encoder: JSONEncoder = JSONEncoder()) throws {
        httpBody = try encoder.encode(object)
        setContentType(.json)
    }
    
    /// Set form URL encoded body
    mutating func setFormBody(_ parameters: [String: String]) {
        let body = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        httpBody = body.data(using: .utf8)
        setContentType(.formUrlEncoded)
    }
    
    /// Set raw body
    mutating func setBody(_ data: Data) {
        httpBody = data
    }
    
    /// Set text body
    mutating func setTextBody(_ text: String, encoding: String.Encoding = .utf8) {
        httpBody = text.data(using: encoding)
        setContentType(.plainText)
    }
    
    // MARK: - Query Parameters
    
    /// Add query parameters
    mutating func addQueryParameters(_ parameters: [String: String]) {
        guard let url = url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        
        let queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        if components.queryItems == nil {
            components.queryItems = queryItems
        } else {
            components.queryItems?.append(contentsOf: queryItems)
        }
        
        self.url = components.url
    }
    
    /// Get query parameters
    var queryParameters: [String: String]? {
        guard let url = url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        var parameters: [String: String] = [:]
        queryItems.forEach { parameters[$0.name] = $0.value }
        return parameters
    }
    
    // MARK: - Caching
    
    /// Set cache policy
    mutating func setCachePolicy(_ policy: CachePolicy) {
        cachePolicy = policy
    }
    
    /// Disable cache
    mutating func disableCache() {
        cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    }
    
    // MARK: - Timeout
    
    /// Set timeout
    mutating func setTimeout(_ interval: TimeInterval) {
        timeoutInterval = interval
    }
    
    // MARK: - User Agent
    
    /// Set user agent
    mutating func setUserAgent(_ userAgent: String) {
        setHeader(userAgent, for: "User-Agent")
    }
    
    /// Set default user agent
    mutating func setDefaultUserAgent() {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
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
        let userAgent = "\(appName)/\(appVersion) (build \(build); \(platform) \(osVersion))"
        setUserAgent(userAgent)
    }
    
    // MARK: - Debugging
    
    /// Get cURL command
    var cURLCommand: String {
        var components = ["curl"]
        
        // Add method
        if let method = httpMethod, method != "GET" {
            components.append("-X \(method)")
        }
        
        // Add headers
        allHTTPHeaderFields?.forEach { key, value in
            components.append("-H '\(key): \(value)'")
        }
        
        // Add body
        if let body = httpBody {
            if let bodyString = String(data: body, encoding: .utf8) {
                components.append("-d '\(bodyString)'")
            } else {
                components.append("-d '<\(body.count) bytes of binary data>'")
            }
        }
        
        // Add URL
        if let url = url {
            components.append("'\(url.absoluteString)'")
        }
        
        return components.joined(separator: " \\\n  ")
    }
    
    /// Get description
    var debugDescription: String {
        var description = "\(httpMethod ?? "GET") \(url?.absoluteString ?? "nil")"
        
        if let headers = allHTTPHeaderFields, !headers.isEmpty {
            description += "\nHeaders:"
            headers.forEach { key, value in
                description += "\n  \(key): \(value)"
            }
        }
        
        if let body = httpBody {
            description += "\nBody:"
            if let bodyString = String(data: body, encoding: .utf8) {
                description += "\n  \(bodyString)"
            } else {
                description += "\n  <\(body.count) bytes>"
            }
        }
        
        return description
    }
    
    // MARK: - Validation
    
    /// Validate request
    func validate() throws {
        guard url != nil else {
            throw NetworkError.invalidRequest("URL is nil")
        }
        
        if let method = httpMethod,
           ["POST", "PUT", "PATCH"].contains(method),
           httpBody == nil {
            // Warning: POST/PUT/PATCH without body
        }
    }
    
    // MARK: - Signing
    
    /// Sign request with HMAC
    mutating func signWithHMAC(key: Data, algorithm: HMACAlgorithm = .sha256) {
        let signature = generateHMACSignature(key: key, algorithm: algorithm)
        setHeader(signature, for: "X-Signature")
    }
    
    /// Generate HMAC signature
    func generateHMACSignature(key: Data, algorithm: HMACAlgorithm) -> String {
        var dataToSign = "\(httpMethod ?? "GET")\n"
        dataToSign += "\(url?.path ?? "")\n"
        
        // Add headers to sign
        if let headers = allHTTPHeaderFields {
            let sortedHeaders = headers.sorted { $0.key < $1.key }
            sortedHeaders.forEach { key, value in
                dataToSign += "\(key.lowercased()):\(value)\n"
            }
        }
        
        // Add body hash
        if let body = httpBody {
            let hash = SHA256.hash(data: body)
            dataToSign += hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        
        guard let data = dataToSign.data(using: .utf8) else {
            return ""
        }
        
        let signature: Data
        switch algorithm {
        case .sha256:
            signature = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
                .withUnsafeBytes { Data($0) }
        case .sha384:
            signature = HMAC<SHA384>.authenticationCode(for: data, using: SymmetricKey(data: key))
                .withUnsafeBytes { Data($0) }
        case .sha512:
            signature = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key))
                .withUnsafeBytes { Data($0) }
        }
        
        return signature.base64EncodedString()
    }
    
    enum HMACAlgorithm {
        case sha256
        case sha384
        case sha512
    }
}

// MARK: - URLRequest Builder

/// Builder for URLRequest
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class URLRequestBuilder {
    
    private var request: URLRequest
    
    public init(url: URL) {
        self.request = URLRequest(url: url)
    }
    
    @discardableResult
    public func method(_ method: HTTPMethod) -> Self {
        request.setMethod(method)
        return self
    }
    
    @discardableResult
    public func header(_ value: String, for field: String) -> Self {
        request.setHeader(value, for: field)
        return self
    }
    
    @discardableResult
    public func headers(_ headers: [String: String]) -> Self {
        request.setHeaders(headers)
        return self
    }
    
    @discardableResult
    public func contentType(_ contentType: URLRequest.ContentType) -> Self {
        request.setContentType(contentType)
        return self
    }
    
    @discardableResult
    public func accept(_ contentType: URLRequest.ContentType) -> Self {
        request.setAccept(contentType)
        return self
    }
    
    @discardableResult
    public func basicAuth(username: String, password: String) -> Self {
        request.setBasicAuth(username: username, password: password)
        return self
    }
    
    @discardableResult
    public func bearerToken(_ token: String) -> Self {
        request.setBearerToken(token)
        return self
    }
    
    @discardableResult
    public func apiKey(_ key: String, header: String = "X-API-Key") -> Self {
        request.setAPIKey(key, header: header)
        return self
    }
    
    @discardableResult
    public func jsonBody<T: Encodable>(_ object: T, encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        try request.setJSONBody(object, encoder: encoder)
        return self
    }
    
    @discardableResult
    public func formBody(_ parameters: [String: String]) -> Self {
        request.setFormBody(parameters)
        return self
    }
    
    @discardableResult
    public func body(_ data: Data) -> Self {
        request.setBody(data)
        return self
    }
    
    @discardableResult
    public func textBody(_ text: String, encoding: String.Encoding = .utf8) -> Self {
        request.setTextBody(text, encoding: encoding)
        return self
    }
    
    @discardableResult
    public func queryParameters(_ parameters: [String: String]) -> Self {
        request.addQueryParameters(parameters)
        return self
    }
    
    @discardableResult
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Self {
        request.setCachePolicy(policy)
        return self
    }
    
    @discardableResult
    public func timeout(_ interval: TimeInterval) -> Self {
        request.setTimeout(interval)
        return self
    }
    
    @discardableResult
    public func userAgent(_ userAgent: String) -> Self {
        request.setUserAgent(userAgent)
        return self
    }
    
    @discardableResult
    public func defaultUserAgent() -> Self {
        request.setDefaultUserAgent()
        return self
    }
    
    public func build() -> URLRequest {
        return request
    }
    
    public func validate() throws -> URLRequest {
        try request.validate()
        return request
    }
}

// MARK: - HTTP Method

/// HTTP methods enum
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"
    
    public var hasBody: Bool {
        switch self {
        case .post, .put, .patch:
            return true
        default:
            return false
        }
    }
}