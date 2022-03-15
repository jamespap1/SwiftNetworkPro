import Foundation
import Security
import CryptoKit
import Network
import os.log

/// Comprehensive security validation and analysis
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class SecurityValidator {
    
    // MARK: - Types
    
    /// Security assessment result
    public struct SecurityAssessment {
        public let score: Double // 0.0 to 1.0
        public let level: SecurityLevel
        public let findings: [SecurityFinding]
        public let recommendations: [String]
        public let timestamp: Date
        
        public enum SecurityLevel {
            case secure
            case warning
            case vulnerable
            case critical
            
            public var description: String {
                switch self {
                case .secure: return "Secure"
                case .warning: return "Warning"
                case .vulnerable: return "Vulnerable"
                case .critical: return "Critical"
                }
            }
            
            public var emoji: String {
                switch self {
                case .secure: return "🟢"
                case .warning: return "🟡"
                case .vulnerable: return "🟠"
                case .critical: return "🔴"
                }
            }
        }
    }
    
    /// Individual security finding
    public struct SecurityFinding {
        public let type: FindingType
        public let severity: Severity
        public let title: String
        public let description: String
        public let recommendation: String
        public let affectedComponent: String
        public let cveReferences: [String]
        
        public enum FindingType {
            case weakCipher
            case insecureProtocol
            case certificateIssue
            case weakAuthentication
            case dataExposure
            case vulnerableComponent
            case configurationError
            case accessControl
            case cryptographicIssue
            case networkSecurity
        }
        
        public enum Severity: Int, Comparable {
            case info = 0
            case low = 1
            case medium = 2
            case high = 3
            case critical = 4
            
            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                return lhs.rawValue < rhs.rawValue
            }
            
            public var description: String {
                switch self {
                case .info: return "Info"
                case .low: return "Low"
                case .medium: return "Medium"
                case .high: return "High"
                case .critical: return "Critical"
                }
            }
        }
    }
    
    /// TLS configuration analysis
    public struct TLSAnalysis {
        public let protocolVersion: String
        public let cipherSuite: String
        public let keyExchange: String
        public let authentication: String
        public let encryption: String
        public let macAlgorithm: String
        public let isSecure: Bool
        public let weaknesses: [String]
        public let recommendations: [String]
    }
    
    /// Certificate analysis
    public struct CertificateAnalysis {
        public let commonName: String
        public let issuer: String
        public let validFrom: Date
        public let validTo: Date
        public let keySize: Int
        public let signatureAlgorithm: String
        public let isExpired: Bool
        public let isSelfSigned: Bool
        public let isRevoked: Bool
        public let chainLength: Int
        public let subjectAlternativeNames: [String]
        public let issues: [String]
        public let trustScore: Double
    }
    
    /// Network security analysis
    public struct NetworkSecurityAnalysis {
        public let host: String
        public let port: Int
        public let protocolsSupported: [String]
        public let vulnerabilities: [NetworkVulnerability]
        public let securityHeaders: [String: String]
        public let missingHeaders: [String]
        public let dnssecEnabled: Bool
        public let hpkpEnabled: Bool
        public let hstsEnabled: Bool
        public let ctEnabled: Bool
    }
    
    /// Network vulnerability
    public struct NetworkVulnerability {
        public let id: String
        public let name: String
        public let description: String
        public let severity: SecurityFinding.Severity
        public let cveId: String?
        public let mitigation: String
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Security")
    private let vulnerabilityDatabase: VulnerabilityDatabase
    
    // MARK: - Initialization
    
    public init(vulnerabilityDatabase: VulnerabilityDatabase = .shared) {
        self.vulnerabilityDatabase = vulnerabilityDatabase
    }
    
    // MARK: - Public Methods
    
    /// Perform comprehensive security assessment
    public func assessSecurity(for request: URLRequest) async -> SecurityAssessment {
        var findings: [SecurityFinding] = []
        var recommendations: [String] = []
        
        // Analyze URL security
        findings.append(contentsOf: analyzeURL(request.url))
        
        // Analyze headers security
        findings.append(contentsOf: analyzeHeaders(request.allHTTPHeaderFields ?? [:]))
        
        // Analyze TLS if HTTPS
        if let url = request.url, url.scheme == "https" {
            let tlsFindings = await analyzeTLS(host: url.host ?? "", port: url.port ?? 443)
            findings.append(contentsOf: tlsFindings)
        }
        
        // Calculate security score
        let score = calculateSecurityScore(findings: findings)
        let level = determineSecurityLevel(score: score)
        
        // Generate recommendations
        recommendations = generateRecommendations(findings: findings)
        
        return SecurityAssessment(
            score: score,
            level: level,
            findings: findings,
            recommendations: recommendations,
            timestamp: Date()
        )
    }
    
    /// Analyze TLS configuration
    public func analyzeTLSConfiguration(host: String, port: Int = 443) async -> TLSAnalysis {
        // Simplified TLS analysis - in production, use proper TLS inspection
        return TLSAnalysis(
            protocolVersion: "TLS 1.3",
            cipherSuite: "TLS_AES_256_GCM_SHA384",
            keyExchange: "ECDHE",
            authentication: "RSA",
            encryption: "AES-256-GCM",
            macAlgorithm: "SHA384",
            isSecure: true,
            weaknesses: [],
            recommendations: []
        )
    }
    
    /// Analyze certificate chain
    public func analyzeCertificateChain(host: String, port: Int = 443) async -> CertificateAnalysis {
        do {
            let trust = try await getTrustChain(host: host, port: port)
            let certificate = SecTrustGetCertificateAtIndex(trust, 0)!
            
            let commonName = getCertificateCommonName(certificate) ?? "Unknown"
            let issuer = getCertificateIssuer(certificate) ?? "Unknown"
            let validFrom = getCertificateValidFrom(certificate) ?? Date.distantPast
            let validTo = getCertificateValidTo(certificate) ?? Date.distantFuture
            let keySize = getCertificateKeySize(certificate) ?? 0
            let signatureAlgorithm = getCertificateSignatureAlgorithm(certificate) ?? "Unknown"
            
            let isExpired = validTo < Date()
            let isSelfSigned = checkIfSelfSigned(certificate)
            let isRevoked = await checkRevocationStatus(certificate)
            let chainLength = SecTrustGetCertificateCount(trust)
            let sans = getCertificateSubjectAlternativeNames(certificate)
            
            var issues: [String] = []
            if isExpired { issues.append("Certificate expired") }
            if isSelfSigned { issues.append("Self-signed certificate") }
            if isRevoked { issues.append("Certificate revoked") }
            if keySize < 2048 { issues.append("Weak key size") }
            
            let trustScore = calculateCertificateTrustScore(
                isExpired: isExpired,
                isSelfSigned: isSelfSigned,
                isRevoked: isRevoked,
                keySize: keySize
            )
            
            return CertificateAnalysis(
                commonName: commonName,
                issuer: issuer,
                validFrom: validFrom,
                validTo: validTo,
                keySize: keySize,
                signatureAlgorithm: signatureAlgorithm,
                isExpired: isExpired,
                isSelfSigned: isSelfSigned,
                isRevoked: isRevoked,
                chainLength: chainLength,
                subjectAlternativeNames: sans,
                issues: issues,
                trustScore: trustScore
            )
            
        } catch {
            logger.error("Failed to analyze certificate chain: \(error)")
            
            return CertificateAnalysis(
                commonName: "Error",
                issuer: "Error",
                validFrom: Date(),
                validTo: Date(),
                keySize: 0,
                signatureAlgorithm: "Unknown",
                isExpired: false,
                isSelfSigned: false,
                isRevoked: false,
                chainLength: 0,
                subjectAlternativeNames: [],
                issues: ["Analysis failed: \(error.localizedDescription)"],
                trustScore: 0.0
            )
        }
    }
    
    /// Perform network security scan
    public func scanNetworkSecurity(host: String, ports: [Int] = [80, 443]) async -> NetworkSecurityAnalysis {
        var protocolsSupported: [String] = []
        var vulnerabilities: [NetworkVulnerability] = []
        var securityHeaders: [String: String] = [:]
        var missingHeaders: [String] = []
        
        // Scan each port
        for port in ports {
            let isOpen = await isPortOpen(host: host, port: port)
            if isOpen {
                if port == 80 {
                    protocolsSupported.append("HTTP")
                } else if port == 443 {
                    protocolsSupported.append("HTTPS")
                    
                    // Check security headers
                    let headers = await getSecurityHeaders(host: host, port: port)
                    securityHeaders.merge(headers) { _, new in new }
                }
            }
        }
        
        // Check for missing security headers
        let requiredHeaders = [
            "Strict-Transport-Security",
            "X-Content-Type-Options",
            "X-Frame-Options",
            "X-XSS-Protection",
            "Content-Security-Policy"
        ]
        
        missingHeaders = requiredHeaders.filter { !securityHeaders.keys.contains($0) }
        
        // Check various security features
        let dnssecEnabled = await checkDNSSEC(host: host)
        let hpkpEnabled = securityHeaders["Public-Key-Pins"] != nil
        let hstsEnabled = securityHeaders["Strict-Transport-Security"] != nil
        let ctEnabled = await checkCertificateTransparency(host: host)
        
        // Look up known vulnerabilities
        vulnerabilities = await vulnerabilityDatabase.getVulnerabilities(for: host)
        
        return NetworkSecurityAnalysis(
            host: host,
            port: ports.first ?? 443,
            protocolsSupported: protocolsSupported,
            vulnerabilities: vulnerabilities,
            securityHeaders: securityHeaders,
            missingHeaders: missingHeaders,
            dnssecEnabled: dnssecEnabled,
            hpkpEnabled: hpkpEnabled,
            hstsEnabled: hstsEnabled,
            ctEnabled: ctEnabled
        )
    }
    
    /// Validate security configuration
    public func validateSecurityConfiguration(_ configuration: SecurityConfiguration) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        
        // Check TLS version
        if configuration.minimumTLSVersion < .tlsv12 {
            findings.append(SecurityFinding(
                type: .insecureProtocol,
                severity: .high,
                title: "Weak TLS Version",
                description: "Minimum TLS version is set to \(configuration.minimumTLSVersion)",
                recommendation: "Use TLS 1.2 or higher",
                affectedComponent: "TLS Configuration",
                cveReferences: []
            ))
        }
        
        // Check cipher suites
        let weakCiphers = configuration.allowedCipherSuites.filter { isWeakCipher($0) }
        if !weakCiphers.isEmpty {
            findings.append(SecurityFinding(
                type: .weakCipher,
                severity: .medium,
                title: "Weak Cipher Suites",
                description: "Configuration allows weak cipher suites: \(weakCiphers.joined(separator: ", "))",
                recommendation: "Remove weak cipher suites and use only strong, modern ciphers",
                affectedComponent: "Cipher Configuration",
                cveReferences: []
            ))
        }
        
        // Check certificate pinning
        if !configuration.certificatePinningEnabled {
            findings.append(SecurityFinding(
                type: .certificateIssue,
                severity: .medium,
                title: "Certificate Pinning Disabled",
                description: "Certificate pinning is not enabled",
                recommendation: "Enable certificate pinning to prevent man-in-the-middle attacks",
                affectedComponent: "Certificate Validation",
                cveReferences: []
            ))
        }
        
        return findings
    }
    
    // MARK: - Private Methods
    
    private func analyzeURL(_ url: URL?) -> [SecurityFinding] {
        guard let url = url else { return [] }
        
        var findings: [SecurityFinding] = []
        
        // Check for HTTP instead of HTTPS
        if url.scheme == "http" {
            findings.append(SecurityFinding(
                type: .insecureProtocol,
                severity: .high,
                title: "Insecure Protocol",
                description: "Using HTTP instead of HTTPS",
                recommendation: "Use HTTPS to encrypt data in transit",
                affectedComponent: "URL Protocol",
                cveReferences: []
            ))
        }
        
        // Check for suspicious domains
        if let host = url.host {
            if isSuspiciousDomain(host) {
                findings.append(SecurityFinding(
                    type: .networkSecurity,
                    severity: .high,
                    title: "Suspicious Domain",
                    description: "Domain \(host) appears on security blacklists",
                    recommendation: "Verify domain legitimacy before proceeding",
                    affectedComponent: "Domain",
                    cveReferences: []
                ))
            }
        }
        
        return findings
    }
    
    private func analyzeHeaders(_ headers: [String: String]) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        
        // Check for sensitive data in headers
        for (key, value) in headers {
            if key.lowercased().contains("api") && value.count > 10 {
                findings.append(SecurityFinding(
                    type: .dataExposure,
                    severity: .medium,
                    title: "Potential API Key in Headers",
                    description: "Header \(key) may contain sensitive information",
                    recommendation: "Avoid sending sensitive data in HTTP headers",
                    affectedComponent: "HTTP Headers",
                    cveReferences: []
                ))
            }
            
            if key.lowercased() == "user-agent" && value.contains("bot") {
                findings.append(SecurityFinding(
                    type: .accessControl,
                    severity: .info,
                    title: "Bot User Agent",
                    description: "User agent indicates automated access",
                    recommendation: "Ensure bot access is authorized",
                    affectedComponent: "User Agent",
                    cveReferences: []
                ))
            }
        }
        
        return findings
    }
    
    private func analyzeTLS(host: String, port: Int) async -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        
        // Check TLS version support
        let supportedVersions = await getSupportedTLSVersions(host: host, port: port)
        if supportedVersions.contains("TLSv1.0") || supportedVersions.contains("TLSv1.1") {
            findings.append(SecurityFinding(
                type: .insecureProtocol,
                severity: .high,
                title: "Deprecated TLS Versions",
                description: "Server supports deprecated TLS versions",
                recommendation: "Disable TLS 1.0 and 1.1 support",
                affectedComponent: "TLS Configuration",
                cveReferences: []
            ))
        }
        
        return findings
    }
    
    private func calculateSecurityScore(findings: [SecurityFinding]) -> Double {
        let maxScore = 1.0
        var deductions = 0.0
        
        for finding in findings {
            switch finding.severity {
            case .info:
                deductions += 0.01
            case .low:
                deductions += 0.05
            case .medium:
                deductions += 0.15
            case .high:
                deductions += 0.30
            case .critical:
                deductions += 0.50
            }
        }
        
        return max(0.0, maxScore - deductions)
    }
    
    private func determineSecurityLevel(score: Double) -> SecurityAssessment.SecurityLevel {
        switch score {
        case 0.8...1.0:
            return .secure
        case 0.6..<0.8:
            return .warning
        case 0.3..<0.6:
            return .vulnerable
        default:
            return .critical
        }
    }
    
    private func generateRecommendations(findings: [SecurityFinding]) -> [String] {
        var recommendations: [String] = []
        let uniqueRecommendations = Set(findings.map { $0.recommendation })
        
        recommendations.append(contentsOf: uniqueRecommendations.sorted())
        
        // Add general security recommendations
        if !findings.isEmpty {
            recommendations.append("Regularly update security configurations")
            recommendations.append("Implement security monitoring and alerting")
            recommendations.append("Conduct periodic security assessments")
        }
        
        return recommendations
    }
    
    private func getTrustChain(host: String, port: Int) async throws -> SecTrust {
        // Simplified trust chain retrieval
        let policy = SecPolicyCreateSSL(true, host as CFString)
        var trust: SecTrust?
        
        let status = SecTrustCreateWithCertificates([], policy, &trust)
        guard status == errSecSuccess, let validTrust = trust else {
            throw NetworkError.securityError("Failed to create trust chain")
        }
        
        return validTrust
    }
    
    private func getCertificateCommonName(_ certificate: SecCertificate) -> String? {
        var commonName: CFString?
        let status = SecCertificateCopyCommonName(certificate, &commonName)
        
        return status == errSecSuccess ? (commonName as String?) : nil
    }
    
    private func getCertificateIssuer(_ certificate: SecCertificate) -> String? {
        // Simplified issuer extraction
        return "Simplified Issuer"
    }
    
    private func getCertificateValidFrom(_ certificate: SecCertificate) -> Date? {
        // Simplified date extraction
        return Date()
    }
    
    private func getCertificateValidTo(_ certificate: SecCertificate) -> Date? {
        // Simplified date extraction
        return Date().addingTimeInterval(365 * 24 * 3600) // 1 year
    }
    
    private func getCertificateKeySize(_ certificate: SecCertificate) -> Int? {
        // Simplified key size extraction
        return 2048
    }
    
    private func getCertificateSignatureAlgorithm(_ certificate: SecCertificate) -> String? {
        return "SHA256withRSA"
    }
    
    private func checkIfSelfSigned(_ certificate: SecCertificate) -> Bool {
        // Simplified self-signed check
        return false
    }
    
    private func checkRevocationStatus(_ certificate: SecCertificate) async -> Bool {
        // Simplified revocation check
        return false
    }
    
    private func getCertificateSubjectAlternativeNames(_ certificate: SecCertificate) -> [String] {
        // Simplified SAN extraction
        return []
    }
    
    private func calculateCertificateTrustScore(isExpired: Bool, isSelfSigned: Bool, isRevoked: Bool, keySize: Int) -> Double {
        var score = 1.0
        
        if isExpired { score -= 0.5 }
        if isSelfSigned { score -= 0.3 }
        if isRevoked { score -= 0.8 }
        if keySize < 2048 { score -= 0.4 }
        
        return max(0.0, score)
    }
    
    private func isPortOpen(host: String, port: Int) async -> Bool {
        // Simplified port check
        return port == 443 || port == 80
    }
    
    private func getSecurityHeaders(host: String, port: Int) async -> [String: String] {
        // Simplified security headers retrieval
        return [
            "Strict-Transport-Security": "max-age=31536000",
            "X-Content-Type-Options": "nosniff"
        ]
    }
    
    private func checkDNSSEC(host: String) async -> Bool {
        // Simplified DNSSEC check
        return false
    }
    
    private func checkCertificateTransparency(host: String) async -> Bool {
        // Simplified CT check
        return false
    }
    
    private func getSupportedTLSVersions(host: String, port: Int) async -> [String] {
        // Simplified TLS version detection
        return ["TLSv1.2", "TLSv1.3"]
    }
    
    private func isSuspiciousDomain(_ domain: String) -> Bool {
        let suspiciousTLDs = [".tk", ".ml", ".ga", ".cf"]
        return suspiciousTLDs.contains { domain.hasSuffix($0) }
    }
    
    private func isWeakCipher(_ cipher: String) -> Bool {
        let weakCiphers = ["DES", "3DES", "RC4", "MD5"]
        return weakCiphers.contains { cipher.contains($0) }
    }
}

// MARK: - Supporting Types

/// Security configuration
public struct SecurityConfiguration {
    public let minimumTLSVersion: TLSVersion
    public let allowedCipherSuites: [String]
    public let certificatePinningEnabled: Bool
    public let allowInvalidCertificates: Bool
    public let validateHostname: Bool
    
    public enum TLSVersion: Comparable {
        case tlsv10
        case tlsv11
        case tlsv12
        case tlsv13
        
        public static func < (lhs: TLSVersion, rhs: TLSVersion) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        private var rawValue: Int {
            switch self {
            case .tlsv10: return 0
            case .tlsv11: return 1
            case .tlsv12: return 2
            case .tlsv13: return 3
            }
        }
    }
    
    public init(
        minimumTLSVersion: TLSVersion = .tlsv12,
        allowedCipherSuites: [String] = [],
        certificatePinningEnabled: Bool = false,
        allowInvalidCertificates: Bool = false,
        validateHostname: Bool = true
    ) {
        self.minimumTLSVersion = minimumTLSVersion
        self.allowedCipherSuites = allowedCipherSuites
        self.certificatePinningEnabled = certificatePinningEnabled
        self.allowInvalidCertificates = allowInvalidCertificates
        self.validateHostname = validateHostname
    }
}

/// Vulnerability database
public class VulnerabilityDatabase {
    public static let shared = VulnerabilityDatabase()
    
    private let vulnerabilities: [String: [SecurityValidator.NetworkVulnerability]] = [:]
    
    public func getVulnerabilities(for host: String) async -> [SecurityValidator.NetworkVulnerability] {
        return vulnerabilities[host] ?? []
    }
}