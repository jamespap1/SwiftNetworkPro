# NetworkDebugger - Advanced Debugging Tools

## Overview

NetworkDebugger is a comprehensive suite of debugging tools designed to help developers inspect, profile, and troubleshoot network operations in SwiftNetworkPro. It provides real-time monitoring, performance profiling, and detailed request/response inspection capabilities.

## Features

### 🔍 Request/Response Inspection

#### Real-time Traffic Monitor
```swift
import SwiftNetworkPro

// Enable network debugging
NetworkDebugger.shared.enable()

// Configure inspection level
NetworkDebugger.shared.configure { config in
    config.logLevel = .verbose
    config.includeHeaders = true
    config.includeBody = true
    config.prettyPrintJSON = true
    config.maxBodySize = 10_000 // bytes
}

// Monitor specific endpoints
NetworkDebugger.shared.filter { request in
    request.url?.host == "api.example.com"
}
```

#### Request Interceptor
```swift
// Intercept and modify requests before sending
NetworkDebugger.shared.interceptRequest { request in
    print("📤 Outgoing: \(request.method) \(request.url?.absoluteString ?? "")")
    
    // Log headers
    request.allHTTPHeaderFields?.forEach { key, value in
        print("  Header: \(key) = \(value)")
    }
    
    // Log body
    if let body = request.httpBody {
        if let json = try? JSONSerialization.jsonObject(with: body) {
            print("  Body: \(json)")
        }
    }
    
    return request // Return modified or original request
}
```

#### Response Inspector
```swift
// Inspect responses before processing
NetworkDebugger.shared.interceptResponse { response, data in
    print("📥 Incoming: \(response.statusCode)")
    
    // Log response time
    if let requestTime = response.requestTime {
        print("  Duration: \(Date().timeIntervalSince(requestTime))s")
    }
    
    // Log response headers
    response.allHeaderFields.forEach { key, value in
        print("  Header: \(key) = \(value)")
    }
    
    // Log response body
    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) {
        print("  Body: \(json)")
    }
}
```

### ⚡ Performance Profiling

#### Network Metrics Collector
```swift
// Enable performance profiling
NetworkProfiler.shared.enable()

// Collect metrics
NetworkProfiler.shared.onMetricsCollected { metrics in
    print("📊 Network Metrics:")
    print("  Request Count: \(metrics.requestCount)")
    print("  Average Latency: \(metrics.averageLatency)ms")
    print("  Success Rate: \(metrics.successRate)%")
    print("  Cache Hit Rate: \(metrics.cacheHitRate)%")
    print("  Total Data: \(metrics.totalBytesTransferred) bytes")
}

// Profile specific operations
NetworkProfiler.shared.profile("UserDataFetch") {
    try await networkClient.get("/users")
}
```

#### Latency Analyzer
```swift
// Analyze network latency patterns
LatencyAnalyzer.shared.analyze { analysis in
    print("⏱️ Latency Analysis:")
    print("  DNS Lookup: \(analysis.dnsLookupTime)ms")
    print("  Connection: \(analysis.connectionTime)ms")
    print("  TLS Handshake: \(analysis.tlsHandshakeTime)ms")
    print("  Request Transfer: \(analysis.requestTransferTime)ms")
    print("  Server Processing: \(analysis.serverProcessingTime)ms")
    print("  Response Transfer: \(analysis.responseTransferTime)ms")
    print("  Total: \(analysis.totalTime)ms")
}
```

#### Memory Profiler
```swift
// Monitor memory usage
MemoryProfiler.shared.monitor { usage in
    print("💾 Memory Usage:")
    print("  Active Requests: \(usage.activeRequests)")
    print("  Cache Size: \(usage.cacheSize) bytes")
    print("  Image Cache: \(usage.imageCacheSize) bytes")
    print("  Response Buffers: \(usage.responseBuffers) bytes")
    print("  Total: \(usage.totalMemory) bytes")
}
```

### 🌐 Network Simulator

#### Condition Simulator
```swift
// Simulate different network conditions
NetworkSimulator.shared.simulate(.poor3G) {
    // Your network code runs under simulated conditions
    let response = try await networkClient.get("/data")
}

// Available conditions
NetworkSimulator.Condition.wifi         // High speed, low latency
NetworkSimulator.Condition.cellular4G   // Moderate speed
NetworkSimulator.Condition.cellular3G   // Slow speed
NetworkSimulator.Condition.poor3G       // Very slow
NetworkSimulator.Condition.edge         // Extremely slow
NetworkSimulator.Condition.offline      // No connection
```

#### Custom Conditions
```swift
// Create custom network conditions
let customCondition = NetworkCondition(
    bandwidth: 1_000_000,  // bytes per second
    latency: 200,          // milliseconds
    packetLoss: 0.05,      // 5% packet loss
    jitter: 50             // milliseconds
)

NetworkSimulator.shared.simulate(customCondition) {
    // Test under custom conditions
}
```

#### Failure Injection
```swift
// Inject network failures for testing
NetworkSimulator.shared.injectFailure { request in
    if request.url?.path == "/flaky-endpoint" {
        // Randomly fail 30% of requests
        if Double.random(in: 0...1) < 0.3 {
            throw NetworkError.connectionLost
        }
    }
    return nil // No failure
}

// Simulate specific errors
NetworkSimulator.shared.simulateError(.timeout, for: "/slow-endpoint")
NetworkSimulator.shared.simulateError(.serverError(500), for: "/broken-endpoint")
```

## Advanced Features

### 🎯 Breakpoints

```swift
// Set network breakpoints
NetworkDebugger.shared.setBreakpoint { request in
    // Pause execution when condition is met
    request.url?.path == "/debug" && request.method == "POST"
} handler: { request in
    // Inspect and optionally modify request
    print("🔴 Breakpoint hit: \(request)")
    
    // Continue, modify, or cancel
    return .continue(request)
    // return .modify(modifiedRequest)
    // return .cancel
}
```

### 📝 Export & Reporting

```swift
// Export network logs
let logs = NetworkDebugger.shared.exportLogs(format: .json)
try logs.write(to: URL(fileURLWithPath: "network-logs.json"))

// Generate HTML report
let report = NetworkDebugger.shared.generateReport()
try report.write(to: URL(fileURLWithPath: "network-report.html"))

// Export HAR (HTTP Archive) format
let har = NetworkDebugger.shared.exportHAR()
try har.write(to: URL(fileURLWithPath: "network.har"))
```

### 🔄 Replay & Recording

```swift
// Record network session
NetworkRecorder.shared.startRecording()

// Perform network operations...

// Stop and save recording
let recording = NetworkRecorder.shared.stopRecording()
try recording.save(to: "session.recording")

// Replay recorded session
let savedRecording = try NetworkRecording.load(from: "session.recording")
NetworkReplayer.shared.replay(savedRecording) { event in
    print("Replaying: \(event)")
}
```

## Integration with Xcode

### Console Integration
```swift
// Enable Xcode console formatting
NetworkDebugger.shared.enableXcodeIntegration()

// Colored output in console
// 🟢 Success: 200 OK
// 🟡 Redirect: 301 Moved
// 🔴 Error: 404 Not Found
// 🟣 Cached: From cache
```

### LLDB Commands
```lldb
# Custom LLDB commands
(lldb) network_inspect_request <request_id>
(lldb) network_show_metrics
(lldb) network_clear_cache
(lldb) network_simulate offline
```

## Best Practices

### Development vs Production

```swift
#if DEBUG
    NetworkDebugger.shared.enable()
    NetworkDebugger.shared.configure { config in
        config.logLevel = .verbose
        config.enableBreakpoints = true
    }
#else
    NetworkDebugger.shared.disable()
#endif
```

### Performance Considerations

1. **Selective Debugging**: Only debug specific endpoints
```swift
NetworkDebugger.shared.filter { request in
    request.url?.path?.hasPrefix("/api/v2") ?? false
}
```

2. **Limit Body Logging**: Avoid logging large payloads
```swift
NetworkDebugger.shared.configure { config in
    config.maxBodySize = 1000 // bytes
    config.excludeLargeResponses = true
}
```

3. **Use Sampling**: Debug a percentage of requests
```swift
NetworkDebugger.shared.setSamplingRate(0.1) // 10% of requests
```

## Troubleshooting Guide

### Common Issues

#### High Memory Usage
```swift
// Solution: Limit debug buffer size
NetworkDebugger.shared.configure { config in
    config.maxBufferSize = 100 // Keep last 100 requests
    config.autoFlush = true
}
```

#### Performance Impact
```swift
// Solution: Use conditional debugging
NetworkDebugger.shared.enableConditionally { request in
    // Only debug slow requests
    request.timeoutInterval > 10
}
```

#### Missing Requests
```swift
// Solution: Check filter configuration
NetworkDebugger.shared.removeAllFilters()
NetworkDebugger.shared.logLevel = .all
```

## CLI Integration

The NetworkDebugger integrates with our CLI tools for advanced debugging:

```bash
# Monitor network traffic
swift-network monitor --filter="api.example.com"

# Analyze performance
swift-network analyze --metrics --export=report.html

# Simulate conditions
swift-network simulate --condition=3g --duration=60

# Replay session
swift-network replay --file=session.recording
```

## Examples

### Debug OAuth Flow
```swift
NetworkDebugger.shared.debugOAuth { phase, data in
    switch phase {
    case .authorization:
        print("🔐 Authorization: \(data)")
    case .tokenExchange:
        print("🎫 Token Exchange: \(data)")
    case .refresh:
        print("🔄 Token Refresh: \(data)")
    case .error(let error):
        print("❌ OAuth Error: \(error)")
    }
}
```

### Monitor WebSocket Traffic
```swift
NetworkDebugger.shared.debugWebSocket { event in
    switch event {
    case .connected(let url):
        print("🔌 Connected: \(url)")
    case .message(let data):
        print("💬 Message: \(data)")
    case .disconnected(let reason):
        print("🔚 Disconnected: \(reason)")
    }
}
```

### Profile GraphQL Queries
```swift
NetworkDebugger.shared.profileGraphQL { query, metrics in
    print("📊 GraphQL Query: \(query.operationName ?? "unnamed")")
    print("  Complexity: \(metrics.complexity)")
    print("  Fields: \(metrics.fieldCount)")
    print("  Depth: \(metrics.depth)")
    print("  Time: \(metrics.executionTime)ms")
}
```

## Related Documentation

- [CLITools.md](CLITools.md) - Command-line utilities
- [DeveloperGuide.md](DeveloperGuide.md) - Best practices and tips
- [Performance Guide](../Guides/Performance.md) - Performance optimization
- [API Reference](NetworkClient.md) - Core networking APIs