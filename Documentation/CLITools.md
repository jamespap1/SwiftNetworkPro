# CLITools - Command-Line Utilities for SwiftNetworkPro

## Overview

SwiftNetworkPro CLI provides powerful command-line tools for code generation, API testing, migration, and development workflow automation. Built with Swift Argument Parser for a modern, intuitive command-line experience.

## Installation

### Using Homebrew
```bash
brew tap swiftnetworkpro/tools
brew install swift-network-cli
```

### Using Swift Package Manager
```bash
git clone https://github.com/SwiftNetworkPro/cli-tools.git
cd cli-tools
swift build -c release
sudo cp .build/release/swift-network /usr/local/bin/
```

### Using Mint
```bash
mint install SwiftNetworkPro/cli-tools@latest
```

## Core Commands

### 🚀 Code Generation

#### Generate Network Client
```bash
# Generate a complete network client from OpenAPI spec
swift-network generate client --spec api.yaml --output Sources/

# Generate with custom configuration
swift-network generate client \
  --spec api.yaml \
  --output Sources/API/ \
  --namespace MyAPI \
  --async-await \
  --include-tests
```

#### Generate Models
```bash
# Generate Codable models from JSON
swift-network generate models --input sample.json --output Models/

# Generate from OpenAPI schema
swift-network generate models --spec api.yaml --output Models/

# With custom options
swift-network generate models \
  --input data.json \
  --output Models/ \
  --immutable \
  --equatable \
  --public-access
```

#### Generate Mocks
```bash
# Generate mock implementations for testing
swift-network generate mocks --protocol NetworkClientProtocol --output Tests/Mocks/

# Generate with custom behavior
swift-network generate mocks \
  --protocol APIServiceProtocol \
  --output Tests/Mocks/ \
  --include-delay \
  --include-failure-modes
```

#### Generate Documentation
```bash
# Generate API documentation
swift-network generate docs --source Sources/ --output docs/

# Generate with custom template
swift-network generate docs \
  --source Sources/ \
  --output docs/ \
  --template jazzy \
  --include-examples
```

### 🧪 API Testing

#### Test Endpoints
```bash
# Test a single endpoint
swift-network test endpoint https://api.example.com/users

# Test with custom headers
swift-network test endpoint \
  https://api.example.com/users \
  --header "Authorization: Bearer token" \
  --header "X-API-Key: key"

# Test with request body
swift-network test endpoint \
  https://api.example.com/users \
  --method POST \
  --body '{"name": "John", "email": "john@example.com"}'
```

#### Run Test Suite
```bash
# Run predefined test suite
swift-network test suite --config tests.yml

# Run with specific environment
swift-network test suite --config tests.yml --env production

# Run parallel tests
swift-network test suite --config tests.yml --parallel --workers 4
```

#### Performance Testing
```bash
# Load test an endpoint
swift-network test performance \
  https://api.example.com/users \
  --requests 1000 \
  --concurrent 10 \
  --duration 60

# Stress test with ramping
swift-network test stress \
  https://api.example.com/users \
  --start-rate 10 \
  --end-rate 100 \
  --ramp-time 300
```

#### Contract Testing
```bash
# Validate API contract
swift-network test contract \
  --spec api.yaml \
  --base-url https://api.example.com

# Test with schema validation
swift-network test contract \
  --spec api.yaml \
  --base-url https://api.example.com \
  --strict-validation \
  --ignore-optional-fields
```

### 🔄 Migration Scripts

#### Migrate from URLSession
```bash
# Analyze existing URLSession code
swift-network migrate analyze --source Sources/

# Perform migration
swift-network migrate urlsession \
  --source Sources/ \
  --output MigratedSources/ \
  --preserve-structure

# Dry run
swift-network migrate urlsession \
  --source Sources/ \
  --dry-run \
  --verbose
```

#### Migrate from Alamofire
```bash
# Migrate Alamofire code to SwiftNetworkPro
swift-network migrate alamofire \
  --source Sources/ \
  --output MigratedSources/ \
  --preserve-apis

# With custom mapping
swift-network migrate alamofire \
  --source Sources/ \
  --output MigratedSources/ \
  --mapping-file migration-map.json
```

#### Version Migration
```bash
# Migrate to latest version
swift-network migrate version --from 1.0 --to 2.0

# Check migration requirements
swift-network migrate check --current-version 1.5

# Generate migration report
swift-network migrate report --output migration-report.html
```

### 📊 Analytics & Monitoring

#### Network Analytics
```bash
# Start monitoring network traffic
swift-network monitor start --port 8080

# View real-time metrics
swift-network monitor metrics --live

# Export analytics data
swift-network monitor export \
  --format csv \
  --output metrics.csv \
  --from "2024-01-01" \
  --to "2024-01-31"
```

#### Performance Analysis
```bash
# Analyze network performance
swift-network analyze performance --log-file network.log

# Generate performance report
swift-network analyze report \
  --input logs/ \
  --output report.html \
  --include-graphs
```

### 🛠️ Development Tools

#### Mock Server
```bash
# Start mock server
swift-network mock start --config mocks.yml --port 3000

# Start with delay simulation
swift-network mock start \
  --config mocks.yml \
  --port 3000 \
  --delay 500 \
  --variance 100
```

#### Proxy Server
```bash
# Start debugging proxy
swift-network proxy start \
  --port 8888 \
  --target https://api.example.com \
  --log-level debug

# With request modification
swift-network proxy start \
  --port 8888 \
  --target https://api.example.com \
  --modify-script proxy-rules.js
```

#### Cache Management
```bash
# Clear network cache
swift-network cache clear

# View cache statistics
swift-network cache stats

# Export cache contents
swift-network cache export --output cache-dump.json

# Import cache contents
swift-network cache import --input cache-dump.json
```

## Advanced Features

### 🔧 Configuration Management

#### Initialize Configuration
```bash
# Create configuration file
swift-network config init

# Initialize with template
swift-network config init --template enterprise
```

#### Manage Environments
```bash
# Add environment
swift-network config env add production \
  --base-url https://api.example.com \
  --timeout 30 \
  --retry-count 3

# List environments
swift-network config env list

# Switch environment
swift-network config env use production
```

### 📝 Code Analysis

#### Analyze Network Usage
```bash
# Analyze network code patterns
swift-network analyze code --source Sources/

# Find inefficiencies
swift-network analyze inefficiencies \
  --source Sources/ \
  --output issues.json
```

#### Security Audit
```bash
# Audit for security issues
swift-network audit security --source Sources/

# Check for common vulnerabilities
swift-network audit vulnerabilities \
  --source Sources/ \
  --include-dependencies
```

### 🚀 CI/CD Integration

#### GitHub Actions
```yaml
# .github/workflows/api-test.yml
name: API Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install CLI
        run: |
          brew tap swiftnetworkpro/tools
          brew install swift-network-cli
      - name: Run API Tests
        run: |
          swift-network test suite --config tests.yml
      - name: Performance Test
        run: |
          swift-network test performance \
            --config perf-tests.yml \
            --threshold-file thresholds.json
```

#### Jenkins Pipeline
```groovy
pipeline {
    agent any
    stages {
        stage('Generate Client') {
            steps {
                sh 'swift-network generate client --spec api.yaml --output Sources/'
            }
        }
        stage('Test') {
            steps {
                sh 'swift-network test suite --config tests.yml'
            }
        }
        stage('Deploy') {
            steps {
                sh 'swift-network deploy --env production'
            }
        }
    }
}
```

## Configuration Files

### Test Configuration (tests.yml)
```yaml
version: 1.0
base_url: https://api.example.com
timeout: 30
retry: 3

environments:
  development:
    base_url: https://dev.api.example.com
  production:
    base_url: https://api.example.com

tests:
  - name: Get Users
    endpoint: /users
    method: GET
    expect:
      status: 200
      headers:
        Content-Type: application/json
      
  - name: Create User
    endpoint: /users
    method: POST
    body:
      name: Test User
      email: test@example.com
    expect:
      status: 201
```

### Mock Configuration (mocks.yml)
```yaml
version: 1.0
port: 3000

endpoints:
  - path: /users
    method: GET
    response:
      status: 200
      headers:
        Content-Type: application/json
      body:
        - id: 1
          name: John Doe
          email: john@example.com
          
  - path: /users/:id
    method: GET
    response:
      status: 200
      body:
        id: ${params.id}
        name: John Doe
        email: john@example.com
```

## Scripting & Automation

### Bash Integration
```bash
#!/bin/bash
# deploy.sh

# Generate client from latest spec
swift-network generate client --spec api.yaml --output Sources/

# Run tests
swift-network test suite --config tests.yml

# Deploy if tests pass
if [ $? -eq 0 ]; then
    swift-network deploy --env production
else
    echo "Tests failed, deployment cancelled"
    exit 1
fi
```

### Python Integration
```python
#!/usr/bin/env python3
# analyze.py

import subprocess
import json

# Run network analysis
result = subprocess.run(
    ['swift-network', 'analyze', 'performance', '--format', 'json'],
    capture_output=True,
    text=True
)

# Parse results
data = json.loads(result.stdout)

# Process metrics
for endpoint in data['endpoints']:
    if endpoint['avg_latency'] > 1000:
        print(f"Slow endpoint: {endpoint['path']} ({endpoint['avg_latency']}ms)")
```

## Plugins & Extensions

### Custom Commands
```swift
// Sources/MyPlugin.swift
import SwiftNetworkCLI

struct MyCustomCommand: Command {
    static let configuration = CommandConfiguration(
        commandName: "my-command",
        abstract: "My custom command"
    )
    
    func run() throws {
        // Custom logic
    }
}

// Register plugin
CLI.register(plugin: MyCustomCommand.self)
```

### Custom Generators
```swift
// Sources/CustomGenerator.swift
import SwiftNetworkCLI

class CustomGenerator: Generator {
    func generate(from spec: Specification) throws -> String {
        // Custom generation logic
        return generatedCode
    }
}

// Register generator
CLI.register(generator: CustomGenerator(), for: "custom")
```

## Troubleshooting

### Common Issues

#### Permission Denied
```bash
# Fix permissions
chmod +x /usr/local/bin/swift-network
```

#### Command Not Found
```bash
# Add to PATH
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### SSL Certificate Issues
```bash
# Disable SSL verification (development only)
swift-network test endpoint https://localhost:8443 --insecure
```

## Best Practices

1. **Version Control**: Always commit generated code
2. **CI/CD Integration**: Automate testing and deployment
3. **Environment Management**: Use separate configs for dev/staging/prod
4. **Security**: Never commit sensitive data in config files
5. **Performance**: Use caching and connection pooling

## Related Documentation

- [NetworkDebugger.md](NetworkDebugger.md) - Debugging tools
- [DeveloperGuide.md](DeveloperGuide.md) - Development best practices
- [API Reference](NetworkClient.md) - Core networking APIs
- [Migration Guide](../Guides/Migration.md) - Migration strategies