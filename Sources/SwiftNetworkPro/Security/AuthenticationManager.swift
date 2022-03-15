import Foundation
import AuthenticationServices
import CryptoKit
import os.log

/// Advanced authentication manager supporting multiple auth strategies
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor AuthenticationManager {
    
    // MARK: - Types
    
    /// Authentication type
    public enum AuthenticationType {
        case none
        case basic(username: String, password: String)
        case bearer(token: String)
        case apiKey(key: String, header: String = "X-API-Key")
        case oauth2(OAuth2Configuration)
        case jwt(JWTConfiguration)
        case custom(headers: [String: String])
    }
    
    /// OAuth2 configuration
    public struct OAuth2Configuration {
        public let clientId: String
        public let clientSecret: String?
        public let authorizationURL: URL
        public let tokenURL: URL
        public let redirectURI: String
        public let scopes: [String]
        public let grantType: OAuth2GrantType
        public let additionalParameters: [String: String]
        
        public init(
            clientId: String,
            clientSecret: String? = nil,
            authorizationURL: URL,
            tokenURL: URL,
            redirectURI: String,
            scopes: [String] = [],
            grantType: OAuth2GrantType = .authorizationCode,
            additionalParameters: [String: String] = [:]
        ) {
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.authorizationURL = authorizationURL
            self.tokenURL = tokenURL
            self.redirectURI = redirectURI
            self.scopes = scopes
            self.grantType = grantType
            self.additionalParameters = additionalParameters
        }
    }
    
    /// OAuth2 grant type
    public enum OAuth2GrantType: String {
        case authorizationCode = "authorization_code"
        case implicit = "implicit"
        case password = "password"
        case clientCredentials = "client_credentials"
        case refreshToken = "refresh_token"
        case deviceCode = "urn:ietf:params:oauth:grant-type:device_code"
    }
    
    /// JWT configuration
    public struct JWTConfiguration {
        public let issuer: String?
        public let audience: String?
        public let algorithm: JWTAlgorithm
        public let privateKey: Data?
        public let publicKey: Data?
        public let expirationTime: TimeInterval
        public let refreshThreshold: TimeInterval
        public let customClaims: [String: Any]
        
        public init(
            issuer: String? = nil,
            audience: String? = nil,
            algorithm: JWTAlgorithm = .hs256,
            privateKey: Data? = nil,
            publicKey: Data? = nil,
            expirationTime: TimeInterval = 3600,
            refreshThreshold: TimeInterval = 300,
            customClaims: [String: Any] = [:]
        ) {
            self.issuer = issuer
            self.audience = audience
            self.algorithm = algorithm
            self.privateKey = privateKey
            self.publicKey = publicKey
            self.expirationTime = expirationTime
            self.refreshThreshold = refreshThreshold
            self.customClaims = customClaims
        }
    }
    
    /// JWT algorithm
    public enum JWTAlgorithm: String {
        case hs256 = "HS256"
        case hs384 = "HS384"
        case hs512 = "HS512"
        case rs256 = "RS256"
        case rs384 = "RS384"
        case rs512 = "RS512"
        case es256 = "ES256"
        case es384 = "ES384"
        case es512 = "ES512"
    }
    
    /// Token storage
    public protocol TokenStorage: Sendable {
        func store(_ token: Token) async throws
        func retrieve() async throws -> Token?
        func delete() async throws
    }
    
    /// Token information
    public struct Token: Codable, Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let tokenType: String
        public let expiresIn: TimeInterval?
        public let expiresAt: Date?
        public let scope: String?
        public let additionalInfo: [String: String]?
        
        public var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() >= expiresAt
        }
        
        public var needsRefresh: Bool {
            guard let expiresAt = expiresAt else { return false }
            let refreshThreshold: TimeInterval = 300 // 5 minutes
            return Date().addingTimeInterval(refreshThreshold) >= expiresAt
        }
        
        public init(
            accessToken: String,
            refreshToken: String? = nil,
            tokenType: String = "Bearer",
            expiresIn: TimeInterval? = nil,
            scope: String? = nil,
            additionalInfo: [String: String]? = nil
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.tokenType = tokenType
            self.expiresIn = expiresIn
            self.expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
            self.scope = scope
            self.additionalInfo = additionalInfo
        }
    }
    
    /// Authentication state
    public enum AuthenticationState {
        case unauthenticated
        case authenticated(Token)
        case refreshing
        case failed(Error)
    }
    
    // MARK: - Properties
    
    private var authenticationType: AuthenticationType
    private var currentToken: Token?
    private var tokenStorage: TokenStorage?
    private var state: AuthenticationState = .unauthenticated
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Authentication")
    private var refreshTask: Task<Token, Error>?
    private var authenticationSession: ASWebAuthenticationSession?
    
    // Callbacks
    private var onTokenRefresh: ((Token) -> Void)?
    private var onAuthenticationFailure: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    public init(
        type: AuthenticationType = .none,
        tokenStorage: TokenStorage? = nil
    ) {
        self.authenticationType = type
        self.tokenStorage = tokenStorage
        
        Task {
            await loadStoredToken()
        }
    }
    
    // MARK: - Public Methods
    
    /// Get authentication headers
    public func getAuthenticationHeaders() async throws -> [String: String] {
        switch authenticationType {
        case .none:
            return [:]
            
        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            guard let data = credentials.data(using: .utf8) else {
                throw AuthenticationError.invalidCredentials
            }
            let base64 = data.base64EncodedString()
            return ["Authorization": "Basic \(base64)"]
            
        case .bearer(let token):
            return ["Authorization": "Bearer \(token)"]
            
        case .apiKey(let key, let header):
            return [header: key]
            
        case .oauth2(let config):
            let token = try await getOAuth2Token(config: config)
            return ["Authorization": "\(token.tokenType) \(token.accessToken)"]
            
        case .jwt(let config):
            let token = try await getJWTToken(config: config)
            return ["Authorization": "Bearer \(token.accessToken)"]
            
        case .custom(let headers):
            return headers
        }
    }
    
    /// Authenticate
    public func authenticate() async throws {
        switch authenticationType {
        case .oauth2(let config):
            let token = try await performOAuth2Authentication(config: config)
            await updateToken(token)
            
        case .jwt(let config):
            let token = try await generateJWT(config: config)
            await updateToken(token)
            
        default:
            // Other auth types don't require explicit authentication
            state = .authenticated(Token(accessToken: ""))
        }
    }
    
    /// Refresh token if needed
    public func refreshTokenIfNeeded() async throws {
        guard let token = currentToken, token.needsRefresh else {
            return
        }
        
        // Avoid multiple simultaneous refresh attempts
        if let existingTask = refreshTask {
            _ = try await existingTask.value
            return
        }
        
        state = .refreshing
        
        refreshTask = Task {
            do {
                let newToken = try await refreshToken(token)
                await updateToken(newToken)
                refreshTask = nil
                return newToken
            } catch {
                state = .failed(error)
                refreshTask = nil
                throw error
            }
        }
        
        _ = try await refreshTask!.value
    }
    
    /// Logout
    public func logout() async {
        currentToken = nil
        state = .unauthenticated
        
        if let tokenStorage = tokenStorage {
            try? await tokenStorage.delete()
        }
        
        logger.info("User logged out")
    }
    
    /// Update authentication type
    public func updateAuthenticationType(_ type: AuthenticationType) {
        self.authenticationType = type
        currentToken = nil
        state = .unauthenticated
    }
    
    /// Set token refresh callback
    public func onTokenRefresh(_ callback: @escaping (Token) -> Void) {
        self.onTokenRefresh = callback
    }
    
    /// Set authentication failure callback
    public func onAuthenticationFailure(_ callback: @escaping (Error) -> Void) {
        self.onAuthenticationFailure = callback
    }
    
    /// Get current authentication state
    public func getState() -> AuthenticationState {
        return state
    }
    
    /// Check if authenticated
    public func isAuthenticated() -> Bool {
        if case .authenticated = state {
            return true
        }
        return false
    }
    
    // MARK: - Private Methods
    
    private func loadStoredToken() async {
        guard let tokenStorage = tokenStorage else { return }
        
        do {
            if let token = try await tokenStorage.retrieve() {
                if !token.isExpired {
                    currentToken = token
                    state = .authenticated(token)
                    logger.info("Loaded stored token")
                } else {
                    logger.info("Stored token is expired")
                    try await tokenStorage.delete()
                }
            }
        } catch {
            logger.error("Failed to load stored token: \(error)")
        }
    }
    
    private func updateToken(_ token: Token) async {
        currentToken = token
        state = .authenticated(token)
        
        // Store token
        if let tokenStorage = tokenStorage {
            do {
                try await tokenStorage.store(token)
            } catch {
                logger.error("Failed to store token: \(error)")
            }
        }
        
        // Notify callback
        onTokenRefresh?(token)
        
        logger.info("Token updated")
    }
    
    // MARK: - OAuth2 Implementation
    
    private func getOAuth2Token(config: OAuth2Configuration) async throws -> Token {
        // Check if we have a valid token
        if let token = currentToken, !token.needsRefresh {
            return token
        }
        
        // Refresh if we have a refresh token
        if let token = currentToken, let refreshToken = token.refreshToken {
            return try await refreshOAuth2Token(config: config, refreshToken: refreshToken)
        }
        
        // Otherwise, authenticate
        return try await performOAuth2Authentication(config: config)
    }
    
    private func performOAuth2Authentication(config: OAuth2Configuration) async throws -> Token {
        switch config.grantType {
        case .authorizationCode:
            return try await performAuthorizationCodeFlow(config: config)
            
        case .clientCredentials:
            return try await performClientCredentialsFlow(config: config)
            
        case .password:
            throw AuthenticationError.unsupportedGrantType("Password grant is not recommended")
            
        case .implicit:
            throw AuthenticationError.unsupportedGrantType("Implicit grant is deprecated")
            
        case .refreshToken:
            throw AuthenticationError.invalidGrantType("Cannot use refresh_token for initial authentication")
            
        case .deviceCode:
            return try await performDeviceCodeFlow(config: config)
        }
    }
    
    @MainActor
    private func performAuthorizationCodeFlow(config: OAuth2Configuration) async throws -> Token {
        // Build authorization URL
        var components = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " "))
        ]
        
        // Add additional parameters
        for (key, value) in config.additionalParameters {
            components.queryItems?.append(URLQueryItem(name: key, value: value))
        }
        
        // Add state for security
        let state = UUID().uuidString
        components.queryItems?.append(URLQueryItem(name: "state", value: state))
        
        guard let authURL = components.url else {
            throw AuthenticationError.invalidConfiguration("Invalid authorization URL")
        }
        
        // Perform authentication
        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            authenticationSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: URL(string: config.redirectURI)?.scheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthenticationError.authenticationCancelled)
                }
            }
            
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = true
            authenticationSession?.start()
        }
        
        // Extract authorization code
        guard let code = extractAuthorizationCode(from: callbackURL) else {
            throw AuthenticationError.missingAuthorizationCode
        }
        
        // Exchange code for token
        return try await exchangeCodeForToken(code: code, config: config)
    }
    
    private func extractAuthorizationCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == "code" })?.value
    }
    
    private func exchangeCodeForToken(code: String, config: OAuth2Configuration) async throws -> Token {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId
        ]
        
        if let clientSecret = config.clientSecret {
            parameters["client_secret"] = clientSecret
        }
        
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthenticationError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        
        return Token(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            expiresIn: tokenResponse.expiresIn,
            scope: tokenResponse.scope
        )
    }
    
    private func performClientCredentialsFlow(config: OAuth2Configuration) async throws -> Token {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Basic authentication for client credentials
        if let clientSecret = config.clientSecret {
            let credentials = "\(config.clientId):\(clientSecret)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        var parameters = [
            "grant_type": "client_credentials",
            "scope": config.scopes.joined(separator: " ")
        ]
        
        // Add additional parameters
        for (key, value) in config.additionalParameters {
            parameters[key] = value
        }
        
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthenticationError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        
        return Token(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            expiresIn: tokenResponse.expiresIn,
            scope: tokenResponse.scope
        )
    }
    
    private func performDeviceCodeFlow(config: OAuth2Configuration) async throws -> Token {
        // Step 1: Request device code
        let deviceCode = try await requestDeviceCode(config: config)
        
        // Step 2: Show user code to user
        logger.info("Please visit \(deviceCode.verificationURI) and enter code: \(deviceCode.userCode)")
        
        // Step 3: Poll for token
        return try await pollForToken(deviceCode: deviceCode, config: config)
    }
    
    private func requestDeviceCode(config: OAuth2Configuration) async throws -> DeviceCodeResponse {
        var request = URLRequest(url: config.authorizationURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": config.clientId,
            "scope": config.scopes.joined(separator: " ")
        ]
        
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthenticationError.deviceCodeRequestFailed
        }
        
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }
    
    private func pollForToken(deviceCode: DeviceCodeResponse, config: OAuth2Configuration) async throws -> Token {
        let interval = deviceCode.interval ?? 5
        let expiresAt = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        
        while Date() < expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            
            do {
                let token = try await checkDeviceCodeStatus(deviceCode: deviceCode, config: config)
                return token
            } catch AuthenticationError.authorizationPending {
                // Continue polling
                continue
            } catch {
                throw error
            }
        }
        
        throw AuthenticationError.deviceCodeExpired
    }
    
    private func checkDeviceCodeStatus(deviceCode: DeviceCodeResponse, config: OAuth2Configuration) async throws -> Token {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var parameters = [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode.deviceCode,
            "client_id": config.clientId
        ]
        
        if let clientSecret = config.clientSecret {
            parameters["client_secret"] = clientSecret
        }
        
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
            
            return Token(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                tokenType: tokenResponse.tokenType ?? "Bearer",
                expiresIn: tokenResponse.expiresIn,
                scope: tokenResponse.scope
            )
        } else {
            let errorResponse = try? JSONDecoder().decode(OAuth2ErrorResponse.self, from: data)
            
            if errorResponse?.error == "authorization_pending" {
                throw AuthenticationError.authorizationPending
            } else if errorResponse?.error == "slow_down" {
                throw AuthenticationError.slowDown
            } else {
                throw AuthenticationError.deviceCodeError(errorResponse?.errorDescription ?? "Unknown error")
            }
        }
    }
    
    private func refreshOAuth2Token(config: OAuth2Configuration, refreshToken: String) async throws -> Token {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        
        if let clientSecret = config.clientSecret {
            parameters["client_secret"] = clientSecret
        }
        
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthenticationError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        
        return Token(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            expiresIn: tokenResponse.expiresIn,
            scope: tokenResponse.scope
        )
    }
    
    // MARK: - JWT Implementation
    
    private func getJWTToken(config: JWTConfiguration) async throws -> Token {
        // Check if we have a valid token
        if let token = currentToken, !token.needsRefresh {
            return token
        }
        
        // Generate new JWT
        return try await generateJWT(config: config)
    }
    
    private func generateJWT(config: JWTConfiguration) async throws -> Token {
        // Create header
        let header = JWTHeader(algorithm: config.algorithm.rawValue)
        let headerData = try JSONEncoder().encode(header)
        let headerBase64 = headerData.base64URLEncodedString()
        
        // Create payload
        var payload = JWTPayload()
        payload.issuer = config.issuer
        payload.audience = config.audience
        payload.issuedAt = Date()
        payload.expirationTime = Date().addingTimeInterval(config.expirationTime)
        payload.notBefore = Date()
        payload.jwtId = UUID().uuidString
        
        // Add custom claims
        for (key, value) in config.customClaims {
            payload.customClaims[key] = value
        }
        
        let payloadData = try JSONEncoder().encode(payload)
        let payloadBase64 = payloadData.base64URLEncodedString()
        
        // Create signature
        let signatureInput = "\(headerBase64).\(payloadBase64)"
        let signature = try signJWT(signatureInput, algorithm: config.algorithm, privateKey: config.privateKey)
        
        // Combine to create JWT
        let jwt = "\(signatureInput).\(signature)"
        
        return Token(
            accessToken: jwt,
            tokenType: "Bearer",
            expiresIn: config.expirationTime
        )
    }
    
    private func signJWT(_ input: String, algorithm: JWTAlgorithm, privateKey: Data?) throws -> String {
        guard let inputData = input.data(using: .utf8) else {
            throw AuthenticationError.jwtSigningFailed("Invalid input")
        }
        
        switch algorithm {
        case .hs256, .hs384, .hs512:
            // HMAC signing
            guard let key = privateKey else {
                throw AuthenticationError.jwtSigningFailed("Missing private key")
            }
            
            let signature: Data
            switch algorithm {
            case .hs256:
                signature = HMAC<SHA256>.authenticationCode(for: inputData, using: SymmetricKey(data: key))
                    .withUnsafeBytes { Data($0) }
            case .hs384:
                signature = HMAC<SHA384>.authenticationCode(for: inputData, using: SymmetricKey(data: key))
                    .withUnsafeBytes { Data($0) }
            case .hs512:
                signature = HMAC<SHA512>.authenticationCode(for: inputData, using: SymmetricKey(data: key))
                    .withUnsafeBytes { Data($0) }
            default:
                throw AuthenticationError.unsupportedAlgorithm(algorithm.rawValue)
            }
            
            return signature.base64URLEncodedString()
            
        case .rs256, .rs384, .rs512, .es256, .es384, .es512:
            // RSA/ECDSA signing - simplified implementation
            // In production, use Security framework for proper implementation
            throw AuthenticationError.unsupportedAlgorithm(algorithm.rawValue)
        }
    }
    
    private func refreshToken(_ token: Token) async throws -> Token {
        switch authenticationType {
        case .oauth2(let config):
            guard let refreshToken = token.refreshToken else {
                throw AuthenticationError.missingRefreshToken
            }
            return try await refreshOAuth2Token(config: config, refreshToken: refreshToken)
            
        case .jwt(let config):
            return try await generateJWT(config: config)
            
        default:
            throw AuthenticationError.refreshNotSupported
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension AuthenticationManager: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIWindow()
        #elseif os(macOS)
        return NSApplication.shared.windows.first ?? NSWindow()
        #else
        fatalError("Unsupported platform")
        #endif
    }
}

// MARK: - Supporting Types

/// OAuth2 token response
private struct OAuth2TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// OAuth2 error response
private struct OAuth2ErrorResponse: Decodable {
    let error: String
    let errorDescription: String?
    
    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// Device code response
private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int?
    
    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

/// JWT header
private struct JWTHeader: Codable {
    let algorithm: String
    let type: String = "JWT"
    
    private enum CodingKeys: String, CodingKey {
        case algorithm = "alg"
        case type = "typ"
    }
}

/// JWT payload
private struct JWTPayload: Codable {
    var issuer: String?
    var subject: String?
    var audience: String?
    var expirationTime: Date?
    var notBefore: Date?
    var issuedAt: Date?
    var jwtId: String?
    var customClaims: [String: Any] = [:]
    
    private enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case subject = "sub"
        case audience = "aud"
        case expirationTime = "exp"
        case notBefore = "nbf"
        case issuedAt = "iat"
        case jwtId = "jti"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(issuer, forKey: .issuer)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(audience, forKey: .audience)
        try container.encodeIfPresent(expirationTime?.timeIntervalSince1970, forKey: .expirationTime)
        try container.encodeIfPresent(notBefore?.timeIntervalSince1970, forKey: .notBefore)
        try container.encodeIfPresent(issuedAt?.timeIntervalSince1970, forKey: .issuedAt)
        try container.encodeIfPresent(jwtId, forKey: .jwtId)
    }
}

/// Authentication errors
public enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case invalidConfiguration(String)
    case unsupportedGrantType(String)
    case invalidGrantType(String)
    case authenticationCancelled
    case missingAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case deviceCodeRequestFailed
    case deviceCodeExpired
    case deviceCodeError(String)
    case authorizationPending
    case slowDown
    case missingRefreshToken
    case refreshNotSupported
    case jwtSigningFailed(String)
    case unsupportedAlgorithm(String)
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials provided"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .unsupportedGrantType(let type):
            return "Unsupported grant type: \(type)"
        case .invalidGrantType(let message):
            return "Invalid grant type: \(message)"
        case .authenticationCancelled:
            return "Authentication was cancelled"
        case .missingAuthorizationCode:
            return "Authorization code not found in callback"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .deviceCodeRequestFailed:
            return "Failed to request device code"
        case .deviceCodeExpired:
            return "Device code has expired"
        case .deviceCodeError(let message):
            return "Device code error: \(message)"
        case .authorizationPending:
            return "Authorization is pending"
        case .slowDown:
            return "Polling too frequently, slow down"
        case .missingRefreshToken:
            return "No refresh token available"
        case .refreshNotSupported:
            return "Token refresh not supported for this authentication type"
        case .jwtSigningFailed(let message):
            return "JWT signing failed: \(message)"
        case .unsupportedAlgorithm(let algorithm):
            return "Unsupported JWT algorithm: \(algorithm)"
        case .invalidResponse:
            return "Invalid response received"
        }
    }
}

// MARK: - Extensions

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}