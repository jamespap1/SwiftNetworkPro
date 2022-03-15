import Foundation
import Security
import CryptoKit
import os.log

/// Certificate pinning manager for enhanced security
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class CertificatePinningManager: NSObject {
    
    // MARK: - Properties
    
    /// Pinning mode
    public enum PinningMode {
        case certificate
        case publicKey
        case both
    }
    
    /// Validation result
    public enum ValidationResult {
        case success
        case failure(reason: String)
        case noPin
    }
    
    /// Pin configuration
    public struct PinConfiguration {
        public let host: String
        public let pins: Set<String>
        public let mode: PinningMode
        public let includeSubdomains: Bool
        public let enforceBackupPins: Bool
        public let maxAge: TimeInterval?
        
        public init(
            host: String,
            pins: Set<String>,
            mode: PinningMode = .publicKey,
            includeSubdomains: Bool = false,
            enforceBackupPins: Bool = true,
            maxAge: TimeInterval? = nil
        ) {
            self.host = host
            self.pins = pins
            self.mode = mode
            self.includeSubdomains = includeSubdomains
            self.enforceBackupPins = enforceBackupPins
            self.maxAge = maxAge
        }
    }
    
    /// Pinning policy
    public struct PinningPolicy {
        public let configurations: [PinConfiguration]
        public let allowSelfSigned: Bool
        public let validateCertificateChain: Bool
        public let checkRevocation: Bool
        public let requireCertificateTransparency: Bool
        
        public init(
            configurations: [PinConfiguration],
            allowSelfSigned: Bool = false,
            validateCertificateChain: Bool = true,
            checkRevocation: Bool = false,
            requireCertificateTransparency: Bool = false
        ) {
            self.configurations = configurations
            self.allowSelfSigned = allowSelfSigned
            self.validateCertificateChain = validateCertificateChain
            self.checkRevocation = checkRevocation
            self.requireCertificateTransparency = requireCertificateTransparency
        }
        
        public static let strict = PinningPolicy(
            configurations: [],
            allowSelfSigned: false,
            validateCertificateChain: true,
            checkRevocation: true,
            requireCertificateTransparency: true
        )
        
        public static let standard = PinningPolicy(
            configurations: [],
            allowSelfSigned: false,
            validateCertificateChain: true,
            checkRevocation: false,
            requireCertificateTransparency: false
        )
        
        public static let relaxed = PinningPolicy(
            configurations: [],
            allowSelfSigned: true,
            validateCertificateChain: false,
            checkRevocation: false,
            requireCertificateTransparency: false
        )
    }
    
    private var policy: PinningPolicy
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "CertificatePinning")
    private var pinnedHosts: [String: PinConfiguration] = [:]
    private var certificateCache: [String: (certificate: SecCertificate, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    // MARK: - Initialization
    
    public init(policy: PinningPolicy = .standard) {
        self.policy = policy
        super.init()
        setupPinnedHosts()
    }
    
    // MARK: - Public Methods
    
    /// Update pinning policy
    public func updatePolicy(_ policy: PinningPolicy) {
        self.policy = policy
        setupPinnedHosts()
        clearCache()
    }
    
    /// Add pin configuration
    public func addPinConfiguration(_ configuration: PinConfiguration) {
        pinnedHosts[configuration.host] = configuration
        logger.info("Added pin configuration for host: \(configuration.host)")
    }
    
    /// Remove pin configuration
    public func removePinConfiguration(for host: String) {
        pinnedHosts.removeValue(forKey: host)
        logger.info("Removed pin configuration for host: \(host)")
    }
    
    /// Validate server trust
    public func validateServerTrust(
        _ serverTrust: SecTrust,
        for host: String
    ) -> ValidationResult {
        logger.debug("Validating server trust for host: \(host)")
        
        // Check if host requires pinning
        guard let configuration = findConfiguration(for: host) else {
            logger.debug("No pin configuration found for host: \(host)")
            return policy.configurations.isEmpty ? .success : .noPin
        }
        
        // Validate certificate chain if required
        if policy.validateCertificateChain {
            let chainValidation = validateCertificateChain(serverTrust)
            if case .failure(let reason) = chainValidation {
                return .failure(reason: "Certificate chain validation failed: \(reason)")
            }
        }
        
        // Check revocation if required
        if policy.checkRevocation {
            let revocationCheck = checkCertificateRevocation(serverTrust)
            if case .failure(let reason) = revocationCheck {
                return .failure(reason: "Certificate revocation check failed: \(reason)")
            }
        }
        
        // Validate based on pinning mode
        switch configuration.mode {
        case .certificate:
            return validateCertificatePin(serverTrust, configuration: configuration)
        case .publicKey:
            return validatePublicKeyPin(serverTrust, configuration: configuration)
        case .both:
            let certResult = validateCertificatePin(serverTrust, configuration: configuration)
            if case .failure = certResult {
                return certResult
            }
            return validatePublicKeyPin(serverTrust, configuration: configuration)
        }
    }
    
    /// Extract pins from server trust
    public func extractPins(from serverTrust: SecTrust) -> (certificates: Set<String>, publicKeys: Set<String>) {
        var certificatePins = Set<String>()
        var publicKeyPins = Set<String>()
        
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }
            
            // Extract certificate pin
            if let certificatePin = extractCertificatePin(from: certificate) {
                certificatePins.insert(certificatePin)
            }
            
            // Extract public key pin
            if let publicKeyPin = extractPublicKeyPin(from: certificate) {
                publicKeyPins.insert(publicKeyPin)
            }
        }
        
        return (certificatePins, publicKeyPins)
    }
    
    /// Generate pin from certificate data
    public func generatePin(from certificateData: Data) -> String? {
        let hash = SHA256.hash(data: certificateData)
        return Data(hash).base64EncodedString()
    }
    
    /// Clear certificate cache
    public func clearCache() {
        certificateCache.removeAll()
        logger.info("Certificate cache cleared")
    }
    
    // MARK: - Private Methods
    
    private func setupPinnedHosts() {
        pinnedHosts.removeAll()
        for configuration in policy.configurations {
            pinnedHosts[configuration.host] = configuration
        }
    }
    
    private func findConfiguration(for host: String) -> PinConfiguration? {
        // Direct match
        if let configuration = pinnedHosts[host] {
            return configuration
        }
        
        // Check subdomains
        for (pinnedHost, configuration) in pinnedHosts {
            if configuration.includeSubdomains && isSubdomain(host, of: pinnedHost) {
                return configuration
            }
        }
        
        return nil
    }
    
    private func isSubdomain(_ host: String, of domain: String) -> Bool {
        return host.hasSuffix(".\(domain)")
    }
    
    private func validateCertificateChain(_ serverTrust: SecTrust) -> ValidationResult {
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        if !isValid {
            let errorDescription = error.map { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
            return .failure(reason: errorDescription ?? "Certificate chain validation failed")
        }
        
        return .success
    }
    
    private func checkCertificateRevocation(_ serverTrust: SecTrust) -> ValidationResult {
        // Create revocation policy
        let revocationPolicy = SecPolicyCreateRevocation(
            kSecRevocationUseAnyAvailableMethod | kSecRevocationRequirePositiveResponse
        )
        
        // Set policy
        var policies = [revocationPolicy]
        SecTrustSetPolicies(serverTrust, policies as CFArray)
        
        // Evaluate
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        if !isValid {
            let errorDescription = error.map { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
            return .failure(reason: errorDescription ?? "Certificate revocation check failed")
        }
        
        return .success
    }
    
    private func validateCertificatePin(
        _ serverTrust: SecTrust,
        configuration: PinConfiguration
    ) -> ValidationResult {
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }
            
            if let pin = extractCertificatePin(from: certificate) {
                if configuration.pins.contains(pin) {
                    logger.debug("Certificate pin validated successfully")
                    return .success
                }
            }
        }
        
        return .failure(reason: "No matching certificate pin found")
    }
    
    private func validatePublicKeyPin(
        _ serverTrust: SecTrust,
        configuration: PinConfiguration
    ) -> ValidationResult {
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }
            
            if let pin = extractPublicKeyPin(from: certificate) {
                if configuration.pins.contains(pin) {
                    logger.debug("Public key pin validated successfully")
                    return .success
                }
            }
        }
        
        if configuration.enforceBackupPins && configuration.pins.count > 1 {
            logger.warning("No backup pins matched")
        }
        
        return .failure(reason: "No matching public key pin found")
    }
    
    private func extractCertificatePin(from certificate: SecCertificate) -> String? {
        let certificateData = SecCertificateCopyData(certificate) as Data
        return generatePin(from: certificateData)
    }
    
    private func extractPublicKeyPin(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }
        
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        
        // Generate SPKI hash (Subject Public Key Info)
        let spkiHeader = Data([
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ])
        
        var spkiData = Data()
        spkiData.append(spkiHeader)
        spkiData.append(publicKeyData)
        
        return generatePin(from: spkiData)
    }
}

// MARK: - URLSession Delegate

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension CertificatePinningManager: URLSessionDelegate {
    
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let host = challenge.protectionSpace.host
        let validationResult = validateServerTrust(serverTrust, for: host)
        
        switch validationResult {
        case .success:
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            
        case .failure(let reason):
            logger.error("Certificate pinning validation failed: \(reason)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            
        case .noPin:
            // No pinning required for this host
            if policy.configurations.isEmpty {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

// MARK: - Certificate Transparency

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension CertificatePinningManager {
    
    /// Signed Certificate Timestamp
    public struct SignedCertificateTimestamp {
        public let version: UInt8
        public let logId: Data
        public let timestamp: Date
        public let signature: Data
        
        public init(version: UInt8, logId: Data, timestamp: Date, signature: Data) {
            self.version = version
            self.logId = logId
            self.timestamp = timestamp
            self.signature = signature
        }
    }
    
    /// Validate certificate transparency
    public func validateCertificateTransparency(
        _ serverTrust: SecTrust,
        requiredSCTCount: Int = 2
    ) -> Bool {
        guard policy.requireCertificateTransparency else {
            return true
        }
        
        // Get the leaf certificate
        guard let leafCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            return false
        }
        
        // Extract SCTs from certificate
        let scts = extractSCTs(from: leafCertificate)
        
        // Validate SCT count
        if scts.count < requiredSCTCount {
            logger.warning("Insufficient SCTs: found \(scts.count), required \(requiredSCTCount)")
            return false
        }
        
        // Validate each SCT
        for sct in scts {
            if !validateSCT(sct) {
                logger.warning("Invalid SCT detected")
                return false
            }
        }
        
        logger.debug("Certificate transparency validation passed with \(scts.count) SCTs")
        return true
    }
    
    private func extractSCTs(from certificate: SecCertificate) -> [SignedCertificateTimestamp] {
        // This is a simplified implementation
        // In production, you would parse the certificate extensions
        // to extract actual SCTs
        return []
    }
    
    private func validateSCT(_ sct: SignedCertificateTimestamp) -> Bool {
        // Validate SCT signature and timestamp
        // This is a simplified implementation
        return true
    }
}

// MARK: - OCSP (Online Certificate Status Protocol)

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension CertificatePinningManager {
    
    /// OCSP response status
    public enum OCSPStatus {
        case good
        case revoked(reason: String, revokedAt: Date)
        case unknown
        case error(String)
    }
    
    /// Check certificate status via OCSP
    public func checkOCSPStatus(for certificate: SecCertificate) async -> OCSPStatus {
        // Extract OCSP responder URL from certificate
        guard let ocspURL = extractOCSPURL(from: certificate) else {
            return .error("No OCSP responder URL found")
        }
        
        // Create OCSP request
        guard let ocspRequest = createOCSPRequest(for: certificate) else {
            return .error("Failed to create OCSP request")
        }
        
        // Send OCSP request
        do {
            let (data, response) = try await URLSession.shared.data(from: ocspURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .error("Invalid OCSP response")
            }
            
            // Parse OCSP response
            return parseOCSPResponse(data)
            
        } catch {
            return .error("OCSP request failed: \(error.localizedDescription)")
        }
    }
    
    private func extractOCSPURL(from certificate: SecCertificate) -> URL? {
        // This is a simplified implementation
        // In production, you would parse the certificate extensions
        // to extract the OCSP responder URL
        return nil
    }
    
    private func createOCSPRequest(for certificate: SecCertificate) -> Data? {
        // Create OCSP request according to RFC 6960
        // This is a simplified implementation
        return nil
    }
    
    private func parseOCSPResponse(_ data: Data) -> OCSPStatus {
        // Parse OCSP response according to RFC 6960
        // This is a simplified implementation
        return .good
    }
}

// MARK: - Security Headers Validation

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class SecurityHeadersValidator {
    
    /// Security header requirements
    public struct Requirements {
        public let requireHTTPS: Bool
        public let requireHSTS: Bool
        public let minHSTSMaxAge: TimeInterval
        public let requireCSP: Bool
        public let requireXFrameOptions: Bool
        public let requireXContentTypeOptions: Bool
        public let requireReferrerPolicy: Bool
        
        public init(
            requireHTTPS: Bool = true,
            requireHSTS: Bool = true,
            minHSTSMaxAge: TimeInterval = 31536000, // 1 year
            requireCSP: Bool = false,
            requireXFrameOptions: Bool = true,
            requireXContentTypeOptions: Bool = true,
            requireReferrerPolicy: Bool = false
        ) {
            self.requireHTTPS = requireHTTPS
            self.requireHSTS = requireHSTS
            self.minHSTSMaxAge = minHSTSMaxAge
            self.requireCSP = requireCSP
            self.requireXFrameOptions = requireXFrameOptions
            self.requireXContentTypeOptions = requireXContentTypeOptions
            self.requireReferrerPolicy = requireReferrerPolicy
        }
        
        public static let strict = Requirements(
            requireHTTPS: true,
            requireHSTS: true,
            minHSTSMaxAge: 63072000, // 2 years
            requireCSP: true,
            requireXFrameOptions: true,
            requireXContentTypeOptions: true,
            requireReferrerPolicy: true
        )
        
        public static let standard = Requirements()
        
        public static let relaxed = Requirements(
            requireHTTPS: false,
            requireHSTS: false,
            requireCSP: false,
            requireXFrameOptions: false,
            requireXContentTypeOptions: false,
            requireReferrerPolicy: false
        )
    }
    
    private let requirements: Requirements
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "SecurityHeaders")
    
    public init(requirements: Requirements = .standard) {
        self.requirements = requirements
    }
    
    /// Validate security headers
    public func validate(_ response: HTTPURLResponse) -> [String] {
        var violations: [String] = []
        
        // Check HTTPS
        if requirements.requireHTTPS {
            if let url = response.url, url.scheme != "https" {
                violations.append("Connection is not using HTTPS")
            }
        }
        
        // Check HSTS
        if requirements.requireHSTS {
            if let hsts = response.value(forHTTPHeaderField: "Strict-Transport-Security") {
                if !validateHSTS(hsts) {
                    violations.append("Invalid HSTS header configuration")
                }
            } else {
                violations.append("Missing Strict-Transport-Security header")
            }
        }
        
        // Check CSP
        if requirements.requireCSP {
            if response.value(forHTTPHeaderField: "Content-Security-Policy") == nil {
                violations.append("Missing Content-Security-Policy header")
            }
        }
        
        // Check X-Frame-Options
        if requirements.requireXFrameOptions {
            if response.value(forHTTPHeaderField: "X-Frame-Options") == nil {
                violations.append("Missing X-Frame-Options header")
            }
        }
        
        // Check X-Content-Type-Options
        if requirements.requireXContentTypeOptions {
            if let header = response.value(forHTTPHeaderField: "X-Content-Type-Options") {
                if header != "nosniff" {
                    violations.append("Invalid X-Content-Type-Options value")
                }
            } else {
                violations.append("Missing X-Content-Type-Options header")
            }
        }
        
        // Check Referrer-Policy
        if requirements.requireReferrerPolicy {
            if response.value(forHTTPHeaderField: "Referrer-Policy") == nil {
                violations.append("Missing Referrer-Policy header")
            }
        }
        
        if !violations.isEmpty {
            logger.warning("Security header violations: \(violations.joined(separator: ", "))")
        }
        
        return violations
    }
    
    private func validateHSTS(_ header: String) -> Bool {
        let components = header.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for component in components {
            if component.hasPrefix("max-age=") {
                let maxAgeString = component.replacingOccurrences(of: "max-age=", with: "")
                if let maxAge = TimeInterval(maxAgeString) {
                    return maxAge >= requirements.minHSTSMaxAge
                }
            }
        }
        
        return false
    }
}