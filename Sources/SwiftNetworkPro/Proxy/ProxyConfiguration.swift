import Foundation
import Network
import os.log

/// Proxy configuration for network requests
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public struct ProxyConfiguration {
    
    // MARK: - Types
    
    /// Proxy type
    public enum ProxyType {
        case http
        case https
        case socks4
        case socks5
        case auto
        
        public var description: String {
            switch self {
            case .http: return "HTTP"
            case .https: return "HTTPS"
            case .socks4: return "SOCKS4"
            case .socks5: return "SOCKS5"
            case .auto: return "Auto"
            }
        }
    }
    
    /// Proxy authentication
    public struct Authentication {
        public let username: String
        public let password: String
        
        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
        
        public var base64Encoded: String {
            let credentials = "\(username):\(password)"
            return Data(credentials.utf8).base64EncodedString()
        }
    }
    
    /// Proxy bypass rules
    public struct BypassRules {
        public let hosts: Set<String>
        public let domains: Set<String>
        public let ipRanges: [IPRange]
        public let includeLocalhost: Bool
        
        public init(
            hosts: Set<String> = [],
            domains: Set<String> = [],
            ipRanges: [IPRange] = [],
            includeLocalhost: Bool = true
        ) {
            self.hosts = hosts
            self.domains = domains
            self.ipRanges = ipRanges
            self.includeLocalhost = includeLocalhost
        }
        
        public func shouldBypass(host: String) -> Bool {
            // Check localhost
            if includeLocalhost && (host == "localhost" || host == "127.0.0.1" || host == "::1") {
                return true
            }
            
            // Check exact host match
            if hosts.contains(host) {
                return true
            }
            
            // Check domain match
            for domain in domains {
                if host.hasSuffix(domain) {
                    return true
                }
            }
            
            // Check IP ranges
            if let ip = IPv4Address(host) ?? IPv6Address(host) {
                for range in ipRanges {
                    if range.contains(ip.rawValue) {
                        return true
                    }
                }
            }
            
            return false
        }
    }
    
    /// IP range for bypass rules
    public struct IPRange {
        public let start: String
        public let end: String
        
        public init(start: String, end: String) {
            self.start = start
            self.end = end
        }
        
        public init(cidr: String) {
            // Parse CIDR notation
            let components = cidr.split(separator: "/")
            if components.count == 2 {
                self.start = String(components[0])
                self.end = String(components[0]) // Simplified
            } else {
                self.start = cidr
                self.end = cidr
            }
        }
        
        func contains(_ ip: Data) -> Bool {
            // Simplified IP range check
            return false
        }
    }
    
    // MARK: - Properties
    
    public let type: ProxyType
    public let host: String
    public let port: Int
    public let authentication: Authentication?
    public let bypassRules: BypassRules
    public let usePAC: Bool
    public let pacURL: URL?
    public let connectionTimeout: TimeInterval
    public let validateCertificate: Bool
    
    // MARK: - Initialization
    
    public init(
        type: ProxyType,
        host: String,
        port: Int,
        authentication: Authentication? = nil,
        bypassRules: BypassRules = BypassRules(),
        usePAC: Bool = false,
        pacURL: URL? = nil,
        connectionTimeout: TimeInterval = 30,
        validateCertificate: Bool = true
    ) {
        self.type = type
        self.host = host
        self.port = port
        self.authentication = authentication
        self.bypassRules = bypassRules
        self.usePAC = usePAC
        self.pacURL = pacURL
        self.connectionTimeout = connectionTimeout
        self.validateCertificate = validateCertificate
    }
    
    // MARK: - Factory Methods
    
    /// Create HTTP proxy configuration
    public static func http(
        host: String,
        port: Int,
        authentication: Authentication? = nil
    ) -> ProxyConfiguration {
        return ProxyConfiguration(
            type: .http,
            host: host,
            port: port,
            authentication: authentication
        )
    }
    
    /// Create HTTPS proxy configuration
    public static func https(
        host: String,
        port: Int,
        authentication: Authentication? = nil
    ) -> ProxyConfiguration {
        return ProxyConfiguration(
            type: .https,
            host: host,
            port: port,
            authentication: authentication
        )
    }
    
    /// Create SOCKS5 proxy configuration
    public static func socks5(
        host: String,
        port: Int,
        authentication: Authentication? = nil
    ) -> ProxyConfiguration {
        return ProxyConfiguration(
            type: .socks5,
            host: host,
            port: port,
            authentication: authentication
        )
    }
    
    /// Create PAC (Proxy Auto-Configuration) proxy
    public static func pac(url: URL) -> ProxyConfiguration {
        return ProxyConfiguration(
            type: .auto,
            host: "",
            port: 0,
            usePAC: true,
            pacURL: url
        )
    }
    
    /// System proxy configuration
    public static var system: ProxyConfiguration? {
        // Get system proxy settings
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        // Check HTTP proxy
        if let httpProxy = proxySettings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let httpPort = proxySettings[kCFNetworkProxiesHTTPPort as String] as? Int {
            return ProxyConfiguration(type: .http, host: httpProxy, port: httpPort)
        }
        
        // Check HTTPS proxy
        if let httpsProxy = proxySettings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let httpsPort = proxySettings[kCFNetworkProxiesHTTPSPort as String] as? Int {
            return ProxyConfiguration(type: .https, host: httpsProxy, port: httpsPort)
        }
        
        // Check SOCKS proxy
        if let socksProxy = proxySettings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let socksPort = proxySettings[kCFNetworkProxiesSOCKSPort as String] as? Int {
            return ProxyConfiguration(type: .socks5, host: socksProxy, port: socksPort)
        }
        
        // Check PAC
        if let pacEnabled = proxySettings[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Int,
           pacEnabled == 1,
           let pacURLString = proxySettings[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String,
           let pacURL = URL(string: pacURLString) {
            return pac(url: pacURL)
        }
        
        return nil
    }
    
    // MARK: - URL Session Configuration
    
    /// Apply proxy to URLSession configuration
    public func apply(to configuration: URLSessionConfiguration) {
        var proxyDict: [String: Any] = [:]
        
        switch type {
        case .http:
            proxyDict[kCFNetworkProxiesHTTPEnable as String] = 1
            proxyDict[kCFNetworkProxiesHTTPProxy as String] = host
            proxyDict[kCFNetworkProxiesHTTPPort as String] = port
            
        case .https:
            proxyDict[kCFNetworkProxiesHTTPSEnable as String] = 1
            proxyDict[kCFNetworkProxiesHTTPSProxy as String] = host
            proxyDict[kCFNetworkProxiesHTTPSPort as String] = port
            
        case .socks4, .socks5:
            proxyDict[kCFNetworkProxiesSOCKSEnable as String] = 1
            proxyDict[kCFNetworkProxiesSOCKSProxy as String] = host
            proxyDict[kCFNetworkProxiesSOCKSPort as String] = port
            
        case .auto:
            if let pacURL = pacURL {
                proxyDict[kCFNetworkProxiesProxyAutoConfigEnable as String] = 1
                proxyDict[kCFNetworkProxiesProxyAutoConfigURLString as String] = pacURL.absoluteString
            }
        }
        
        // Add bypass list
        var exceptionsList: [String] = []
        exceptionsList.append(contentsOf: bypassRules.hosts)
        exceptionsList.append(contentsOf: bypassRules.domains)
        
        if bypassRules.includeLocalhost {
            exceptionsList.append("localhost")
            exceptionsList.append("127.0.0.1")
            exceptionsList.append("::1")
        }
        
        if !exceptionsList.isEmpty {
            proxyDict[kCFNetworkProxiesExceptionsList as String] = exceptionsList
        }
        
        configuration.connectionProxyDictionary = proxyDict
    }
}

/// Proxy manager for handling proxy connections
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor ProxyManager {
    
    // MARK: - Properties
    
    private var configurations: [String: ProxyConfiguration] = [:]
    private var activeProxy: ProxyConfiguration?
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Proxy")
    
    // MARK: - Public Methods
    
    /// Add proxy configuration
    public func addProxy(name: String, configuration: ProxyConfiguration) {
        configurations[name] = configuration
        logger.info("Added proxy configuration: \(name)")
    }
    
    /// Remove proxy configuration
    public func removeProxy(name: String) {
        configurations.removeValue(forKey: name)
        if activeProxy != nil && getActiveProxyName() == name {
            activeProxy = nil
        }
        logger.info("Removed proxy configuration: \(name)")
    }
    
    /// Set active proxy
    public func setActiveProxy(name: String) throws {
        guard let configuration = configurations[name] else {
            throw NetworkError.proxyError("Proxy configuration not found: \(name)")
        }
        activeProxy = configuration
        logger.info("Set active proxy: \(name)")
    }
    
    /// Clear active proxy
    public func clearActiveProxy() {
        activeProxy = nil
        logger.info("Cleared active proxy")
    }
    
    /// Get active proxy
    public func getActiveProxy() -> ProxyConfiguration? {
        return activeProxy
    }
    
    /// Get active proxy name
    public func getActiveProxyName() -> String? {
        guard let activeProxy = activeProxy else { return nil }
        
        for (name, config) in configurations {
            if config.host == activeProxy.host && config.port == activeProxy.port {
                return name
            }
        }
        return nil
    }
    
    /// Get all proxy configurations
    public func getAllProxies() -> [String: ProxyConfiguration] {
        return configurations
    }
    
    /// Test proxy connection
    public func testProxy(_ configuration: ProxyConfiguration, testURL: URL? = nil) async -> Bool {
        let url = testURL ?? URL(string: "https://www.google.com")!
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        configuration.apply(to: sessionConfig)
        sessionConfig.timeoutIntervalForRequest = configuration.connectionTimeout
        
        let session = URLSession(configuration: sessionConfig)
        
        do {
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                let success = (200...299).contains(httpResponse.statusCode)
                logger.info("Proxy test \(success ? "succeeded" : "failed"): \(configuration.host):\(configuration.port)")
                return success
            }
            
            return false
            
        } catch {
            logger.error("Proxy test failed: \(error)")
            return false
        }
    }
    
    /// Create URLSession with proxy
    public func createSession(
        proxyName: String? = nil,
        configuration: URLSessionConfiguration = .default
    ) throws -> URLSession {
        let proxy: ProxyConfiguration?
        
        if let name = proxyName {
            guard let namedProxy = configurations[name] else {
                throw NetworkError.proxyError("Proxy configuration not found: \(name)")
            }
            proxy = namedProxy
        } else {
            proxy = activeProxy
        }
        
        if let proxy = proxy {
            proxy.apply(to: configuration)
        }
        
        return URLSession(configuration: configuration)
    }
    
    /// Detect proxy from PAC script
    public func detectProxyFromPAC(
        pacURL: URL,
        for targetURL: URL
    ) async throws -> ProxyConfiguration? {
        // Download PAC script
        let (data, _) = try await URLSession.shared.data(from: pacURL)
        
        guard let pacScript = String(data: data, encoding: .utf8) else {
            throw NetworkError.proxyError("Invalid PAC script")
        }
        
        // Parse PAC script (simplified)
        let proxy = try parsePACScript(pacScript, for: targetURL)
        
        return proxy
    }
    
    // MARK: - Private Methods
    
    private func parsePACScript(_ script: String, for url: URL) throws -> ProxyConfiguration? {
        // This is a simplified PAC parser
        // In production, you would use a JavaScript engine to evaluate the PAC script
        
        if script.contains("DIRECT") {
            return nil
        }
        
        if script.contains("PROXY") {
            // Extract proxy host and port from script
            let pattern = #"PROXY\s+([^:]+):(\d+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
                  match.numberOfRanges > 2 else {
                return nil
            }
            
            let hostRange = match.range(at: 1)
            let portRange = match.range(at: 2)
            
            guard let hostSwiftRange = Range(hostRange, in: script),
                  let portSwiftRange = Range(portRange, in: script),
                  let port = Int(script[portSwiftRange]) else {
                return nil
            }
            
            let host = String(script[hostSwiftRange])
            
            return ProxyConfiguration(type: .http, host: host, port: port)
        }
        
        return nil
    }
}

// MARK: - Proxy Tunneling

/// CONNECT proxy tunneling for HTTPS through HTTP proxy
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class ProxyTunnel {
    
    private let proxyHost: String
    private let proxyPort: Int
    private let targetHost: String
    private let targetPort: Int
    private let authentication: ProxyConfiguration.Authentication?
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "ProxyTunnel")
    
    public init(
        proxyHost: String,
        proxyPort: Int,
        targetHost: String,
        targetPort: Int,
        authentication: ProxyConfiguration.Authentication? = nil
    ) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.authentication = authentication
    }
    
    /// Establish CONNECT tunnel
    public func establishTunnel() async throws -> NWConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(proxyHost),
            port: NWEndpoint.Port(integerLiteral: UInt16(proxyPort))
        )
        
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        do {
                            try await self.sendConnectRequest(connection: connection)
                            continuation.resume(returning: connection)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    
                case .failed(let error):
                    continuation.resume(throwing: error)
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
        }
    }
    
    private func sendConnectRequest(connection: NWConnection) async throws {
        var request = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\n"
        request += "Host: \(targetHost):\(targetPort)\r\n"
        
        if let auth = authentication {
            request += "Proxy-Authorization: Basic \(auth.base64Encoded)\r\n"
        }
        
        request += "\r\n"
        
        guard let data = request.data(using: .utf8) else {
            throw NetworkError.proxyError("Failed to create CONNECT request")
        }
        
        try await connection.send(content: data)
        
        // Read response
        let response = try await connection.receive()
        
        guard let responseData = response,
              let responseString = String(data: responseData, encoding: .utf8),
              responseString.contains("200") else {
            throw NetworkError.proxyError("CONNECT tunnel failed")
        }
        
        logger.info("CONNECT tunnel established to \(targetHost):\(targetPort)")
    }
}

// MARK: - NWConnection Extensions

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension NWConnection {
    
    func send(content: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.send(content: content, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            self.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}