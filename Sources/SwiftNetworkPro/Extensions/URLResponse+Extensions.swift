import Foundation

/// URLResponse extensions for SwiftNetworkPro
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public extension URLResponse {
    
    /// Check if response is successful
    var isSuccess: Bool {
        guard let httpResponse = self as? HTTPURLResponse else { return false }
        return (200...299).contains(httpResponse.statusCode)
    }
    
    /// Check if response is redirect
    var isRedirect: Bool {
        guard let httpResponse = self as? HTTPURLResponse else { return false }
        return (300...399).contains(httpResponse.statusCode)
    }
    
    /// Check if response is client error
    var isClientError: Bool {
        guard let httpResponse = self as? HTTPURLResponse else { return false }
        return (400...499).contains(httpResponse.statusCode)
    }
    
    /// Check if response is server error
    var isServerError: Bool {
        guard let httpResponse = self as? HTTPURLResponse else { return false }
        return (500...599).contains(httpResponse.statusCode)
    }
    
    /// Check if response is error
    var isError: Bool {
        return isClientError || isServerError
    }
}

/// HTTPURLResponse extensions
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public extension HTTPURLResponse {
    
    // MARK: - Status Code Categories
    
    /// Status code category
    var statusCodeCategory: StatusCodeCategory {
        switch statusCode {
        case 100...199: return .informational
        case 200...299: return .success
        case 300...399: return .redirect
        case 400...499: return .clientError
        case 500...599: return .serverError
        default: return .unknown
        }
    }
    
    enum StatusCodeCategory {
        case informational
        case success
        case redirect
        case clientError
        case serverError
        case unknown
        
        public var description: String {
            switch self {
            case .informational: return "Informational"
            case .success: return "Success"
            case .redirect: return "Redirect"
            case .clientError: return "Client Error"
            case .serverError: return "Server Error"
            case .unknown: return "Unknown"
            }
        }
    }
    
    /// Status code description
    var statusCodeDescription: String {
        switch statusCode {
        // 1xx Informational
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 102: return "Processing"
        case 103: return "Early Hints"
        
        // 2xx Success
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 207: return "Multi-Status"
        case 208: return "Already Reported"
        case 226: return "IM Used"
        
        // 3xx Redirect
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        
        // 4xx Client Error
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 418: return "I'm a teapot"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Entity"
        case 423: return "Locked"
        case 424: return "Failed Dependency"
        case 425: return "Too Early"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"
        
        // 5xx Server Error
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 506: return "Variant Also Negotiates"
        case 507: return "Insufficient Storage"
        case 508: return "Loop Detected"
        case 510: return "Not Extended"
        case 511: return "Network Authentication Required"
        
        default: return "Unknown Status Code"
        }
    }
    
    // MARK: - Headers
    
    /// Get header value (case-insensitive)
    func header(for field: String) -> String? {
        let lowercasedField = field.lowercased()
        for (key, value) in allHeaderFields {
            if (key as? String)?.lowercased() == lowercasedField {
                return value as? String
            }
        }
        return nil
    }
    
    /// Get all headers as dictionary
    var headers: [String: String] {
        var headers: [String: String] = [:]
        allHeaderFields.forEach { key, value in
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return headers
    }
    
    /// Get content type
    var contentType: String? {
        return header(for: "Content-Type")
    }
    
    /// Get content length
    var contentLength: Int64? {
        guard let value = header(for: "Content-Length"),
              let length = Int64(value) else {
            return nil
        }
        return length
    }
    
    /// Get content encoding
    var contentEncoding: String? {
        return header(for: "Content-Encoding")
    }
    
    /// Get ETag
    var etag: String? {
        return header(for: "ETag")
    }
    
    /// Get last modified date
    var lastModified: Date? {
        guard let value = header(for: "Last-Modified") else { return nil }
        return DateFormatter.httpDateFormatter.date(from: value)
    }
    
    /// Get expires date
    var expires: Date? {
        guard let value = header(for: "Expires") else { return nil }
        return DateFormatter.httpDateFormatter.date(from: value)
    }
    
    /// Get cache control
    var cacheControl: CacheControl? {
        guard let value = header(for: "Cache-Control") else { return nil }
        return CacheControl(rawValue: value)
    }
    
    /// Get location header
    var location: URL? {
        guard let value = header(for: "Location") else { return nil }
        return URL(string: value)
    }
    
    /// Get server header
    var server: String? {
        return header(for: "Server")
    }
    
    /// Get rate limit headers
    var rateLimitInfo: RateLimitInfo? {
        guard let limit = header(for: "X-RateLimit-Limit"),
              let limitInt = Int(limit) else {
            return nil
        }
        
        let remaining = header(for: "X-RateLimit-Remaining").flatMap { Int($0) }
        let reset = header(for: "X-RateLimit-Reset").flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
        let retryAfter = header(for: "Retry-After").flatMap { Int($0) }
        
        return RateLimitInfo(
            limit: limitInt,
            remaining: remaining,
            reset: reset,
            retryAfter: retryAfter
        )
    }
    
    /// Get cookies
    var cookies: [HTTPCookie] {
        guard let url = url else { return [] }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    }
    
    // MARK: - Debugging
    
    /// Debug description
    var debugDescription: String {
        var description = "HTTP \(statusCode) \(statusCodeDescription)"
        description += "\nURL: \(url?.absoluteString ?? "nil")"
        
        if !headers.isEmpty {
            description += "\nHeaders:"
            headers.forEach { key, value in
                description += "\n  \(key): \(value)"
            }
        }
        
        return description
    }
}

// MARK: - Supporting Types

/// Cache control
public struct CacheControl {
    public let rawValue: String
    
    public var maxAge: Int? {
        return extractValue(for: "max-age").flatMap { Int($0) }
    }
    
    public var sMaxAge: Int? {
        return extractValue(for: "s-maxage").flatMap { Int($0) }
    }
    
    public var isPublic: Bool {
        return rawValue.contains("public")
    }
    
    public var isPrivate: Bool {
        return rawValue.contains("private")
    }
    
    public var noCache: Bool {
        return rawValue.contains("no-cache")
    }
    
    public var noStore: Bool {
        return rawValue.contains("no-store")
    }
    
    public var noTransform: Bool {
        return rawValue.contains("no-transform")
    }
    
    public var mustRevalidate: Bool {
        return rawValue.contains("must-revalidate")
    }
    
    public var proxyRevalidate: Bool {
        return rawValue.contains("proxy-revalidate")
    }
    
    public var immutable: Bool {
        return rawValue.contains("immutable")
    }
    
    private func extractValue(for directive: String) -> String? {
        let pattern = "\(directive)=([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawValue, range: NSRange(rawValue.startIndex..., in: rawValue)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: rawValue) else {
            return nil
        }
        
        return String(rawValue[swiftRange])
    }
}

/// Rate limit information
public struct RateLimitInfo {
    public let limit: Int
    public let remaining: Int?
    public let reset: Date?
    public let retryAfter: Int?
    
    public var isExceeded: Bool {
        return remaining.map { $0 <= 0 } ?? false
    }
    
    public var resetTimeRemaining: TimeInterval? {
        return reset?.timeIntervalSinceNow
    }
}

// MARK: - Date Formatter

private extension DateFormatter {
    static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}