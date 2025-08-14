# Contributing to SwiftNetworkPro

We love your input! We want to make contributing to SwiftNetworkPro as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## 🚀 Quick Start

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/SwiftNetworkPro.git`
3. **Create** a feature branch: `git checkout -b feature/amazing-feature`
4. **Make** your changes
5. **Test** your changes thoroughly
6. **Commit** your changes: `git commit -m 'Add amazing feature'`
7. **Push** to your branch: `git push origin feature/amazing-feature`
8. **Open** a Pull Request

## 🐛 Reporting Bugs

We use GitHub Issues to track bugs. Report a bug by [opening a new issue](https://github.com/muhittincamdali/SwiftNetworkPro/issues/new?template=bug_report.md).

### Before Reporting a Bug

- **Check existing issues** to avoid duplicates
- **Update to the latest version** to see if the issue persists
- **Test in a clean environment** to isolate the problem

### Bug Report Guidelines

Please include:

- **Clear title** describing the issue
- **Steps to reproduce** the behavior
- **Expected behavior** vs **actual behavior**
- **Environment details** (iOS version, Xcode version, Swift version)
- **Code samples** or **test cases** that demonstrate the issue
- **Error messages** or **logs** if available

## 💡 Suggesting Features

We welcome feature suggestions! Please:

1. **Check existing issues** for similar requests
2. **Open a new issue** with the `feature request` label
3. **Describe the problem** you're trying to solve
4. **Explain your proposed solution**
5. **Consider alternative solutions**

### Feature Request Template

```markdown
## Problem
Clear description of the problem this feature would solve.

## Solution
Detailed description of your proposed solution.

## Alternatives
Alternative solutions you've considered.

## Additional Context
Screenshots, mockups, or additional context.
```

## 🔧 Development Setup

### Prerequisites

- **Xcode 15.0+**
- **Swift 5.9+**
- **iOS 15.0+** deployment target
- **macOS 13.0+** for development

### Setup Instructions

1. **Clone the repository**:
   ```bash
   git clone https://github.com/muhittincamdali/SwiftNetworkPro.git
   cd SwiftNetworkPro
   ```

2. **Open in Xcode**:
   ```bash
   open Package.swift
   ```

3. **Build the project**:
   - Press `Cmd+B` or use `Product > Build`

4. **Run tests**:
   - Press `Cmd+U` or use `Product > Test`

### Project Structure

```
SwiftNetworkPro/
├── Sources/SwiftNetworkPro/          # Main source code
│   ├── Core/                         # Core networking functionality
│   ├── WebSocket/                    # WebSocket implementation
│   ├── GraphQL/                      # GraphQL client
│   ├── HTTP2/                        # HTTP/2 protocol support
│   ├── Security/                     # Security and authentication
│   ├── Cache/                        # Caching mechanisms
│   └── Analysis/                     # Traffic analysis and monitoring
├── Tests/SwiftNetworkProTests/       # Unit and integration tests
├── Examples/                         # Example applications
└── Documentation/                    # Detailed documentation
```

## ✅ Code Guidelines

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/):

- **Use clear, descriptive names** for types, methods, and properties
- **Prefer clarity over brevity** in naming
- **Use camelCase** for methods and properties
- **Use PascalCase** for types and protocols
- **Include parameter labels** that make call sites readable

### Code Quality Standards

- **Write self-documenting code** with clear variable and method names
- **Add documentation comments** for public APIs using Swift DocC format
- **Include unit tests** for all new functionality
- **Maintain test coverage** above 80%
- **Use async/await** for asynchronous operations
- **Follow SOLID principles** and clean architecture patterns

### Example Code Style

```swift
/// Performs a network request with the specified configuration
/// - Parameters:
///   - endpoint: The API endpoint to call
///   - method: HTTP method to use
///   - parameters: Query parameters or request body
/// - Returns: Decoded response of the specified type
/// - Throws: NetworkError if the request fails
public func request<T: Decodable>(
    _ endpoint: String,
    method: HTTPMethod,
    parameters: [String: Any]? = nil
) async throws -> T {
    // Implementation
}
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
swift test

# Run tests in Xcode
# Press Cmd+U or use Product > Test
```

### Test Requirements

- **Unit tests** for all new functionality
- **Integration tests** for complex workflows
- **Performance tests** for critical paths
- **Mock objects** for external dependencies
- **Test coverage** above 80%

### Test Structure

```swift
import XCTest
@testable import SwiftNetworkPro

final class NetworkClientTests: XCTestCase {
    var client: NetworkClient!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        client = NetworkClient(session: mockSession)
    }
    
    func testSuccessfulGETRequest() async throws {
        // Test implementation
    }
}
```

## 📝 Documentation

### Documentation Requirements

- **Public APIs** must have Swift DocC documentation
- **Complex algorithms** should include inline comments
- **Architecture decisions** should be documented in ADRs
- **API changes** must be reflected in the changelog

### Documentation Style

```swift
/// A high-performance networking client for iOS applications.
///
/// `NetworkClient` provides a modern, async/await-based API for making
/// HTTP requests. It supports advanced features like automatic retries,
/// request interception, and intelligent caching.
///
/// ## Usage
///
/// ```swift
/// let client = NetworkClient.shared
/// let users = try await client.get("/users", as: [User].self)
/// ```
///
/// ## Thread Safety
///
/// `NetworkClient` is an actor and is safe to use from multiple concurrent contexts.
public actor NetworkClient {
    // Implementation
}
```

## 🎯 Pull Request Process

### Before Submitting

1. **Update documentation** for any public API changes
2. **Add tests** for new functionality
3. **Update CHANGELOG.md** with your changes
4. **Ensure all tests pass** locally
5. **Verify code style** follows guidelines
6. **Check for breaking changes**

### Pull Request Guidelines

- **Use a clear title** describing the change
- **Reference issues** that the PR addresses
- **Describe the changes** in detail
- **Include testing instructions**
- **Add screenshots** for UI changes
- **Keep PRs focused** - one feature per PR

### PR Template

```markdown
## Description
Brief description of the changes and why they're needed.

## Related Issues
Fixes #123
Related to #456

## Changes Made
- [ ] Added new feature X
- [ ] Fixed bug Y
- [ ] Updated documentation

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Screenshots
(If applicable)

## Breaking Changes
(If any)
```

## 🔄 Review Process

### Review Criteria

- **Code quality** and adherence to guidelines
- **Test coverage** and test quality
- **Documentation** completeness
- **Performance** impact
- **Security** considerations
- **API design** consistency

### Review Timeline

- **Initial review**: Within 48 hours
- **Follow-up reviews**: Within 24 hours
- **Merge timeline**: 3-5 business days for standard PRs

## 🏷️ Version Management

We use [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality
- **PATCH** version for backwards-compatible bug fixes

### Release Process

1. **Update version** in `Package.swift`
2. **Update CHANGELOG.md** with release notes
3. **Create release tag**: `git tag v1.2.3`
4. **Push tag**: `git push origin v1.2.3`
5. **Create GitHub release** with release notes

## 🤝 Community Guidelines

### Code of Conduct

- **Be respectful** and inclusive
- **Welcome newcomers** and help them learn
- **Give constructive feedback**
- **Focus on the code**, not the person
- **Assume positive intent**

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and community discussion
- **Pull Request Comments**: Code review and discussion
- **Email**: For security vulnerabilities or sensitive issues

## 🚀 Recognition

Contributors are recognized in:

- **CONTRIBUTORS.md** file
- **Release notes** for significant contributions
- **GitHub contributors** graph
- **Special recognition** for outstanding contributions

## 📞 Need Help?

- **Documentation**: Check our [comprehensive docs](Documentation/)
- **Examples**: Look at [example projects](Examples/)
- **Issues**: Search [existing issues](https://github.com/muhittincamdali/SwiftNetworkPro/issues)
- **Discussions**: Join [GitHub Discussions](https://github.com/muhittincamdali/SwiftNetworkPro/discussions)

## 📄 License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.

---

Thank you for contributing to SwiftNetworkPro! 🎉