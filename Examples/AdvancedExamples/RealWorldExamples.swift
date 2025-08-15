//
//  RealWorldExamples.swift
//  SwiftNetworkPro Advanced Examples
//
//  Created by SwiftNetworkPro on 2024.
//  Copyright © 2024 SwiftNetworkPro. All rights reserved.
//

import SwiftUI
import SwiftNetworkPro
import Combine
import Foundation

/// Real-world examples demonstrating SwiftNetworkPro in production scenarios
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct RealWorldExamplesView: View {
    @StateObject private var ecommerceVM = EcommerceViewModel()
    @StateObject private var socialMediaVM = SocialMediaViewModel()
    @StateObject private var newsVM = NewsAppViewModel()
    @StateObject private var financeVM = FinanceAppViewModel()
    
    var body: some View {
        NavigationView {
            List {
                Section("E-commerce Platform") {
                    NavigationLink("Product Catalog & Shopping") {
                        EcommerceExampleView(viewModel: ecommerceVM)
                    }
                }
                
                Section("Social Media App") {
                    NavigationLink("Real-time Feed & Messaging") {
                        SocialMediaExampleView(viewModel: socialMediaVM)
                    }
                }
                
                Section("News Application") {
                    NavigationLink("Content Delivery & Offline Reading") {
                        NewsAppExampleView(viewModel: newsVM)
                    }
                }
                
                Section("Financial Trading App") {
                    NavigationLink("Real-time Market Data") {
                        FinanceAppExampleView(viewModel: financeVM)
                    }
                }
                
                Section("Enterprise Integration") {
                    NavigationLink("Multi-tenant SaaS Platform") {
                        EnterpriseExampleView()
                    }
                }
            }
            .navigationTitle("Real-World Examples")
        }
    }
}

// MARK: - E-commerce Platform Example

/// E-commerce platform with product catalog, cart, and payment processing
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct EcommerceExampleView: View {
    @ObservedObject var viewModel: EcommerceViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Performance Metrics Dashboard
                PerformanceMetricsView(metrics: viewModel.performanceMetrics)
                
                // Product Search
                ProductSearchView(viewModel: viewModel)
                
                // Product Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    ForEach(viewModel.products, id: \.id) { product in
                        ProductCardView(product: product) {
                            await viewModel.addToCart(product)
                        }
                    }
                }
                
                // Shopping Cart
                if !viewModel.cartItems.isEmpty {
                    CartView(items: viewModel.cartItems) {
                        await viewModel.checkout()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("E-commerce Demo")
        .task {
            await viewModel.loadProducts()
        }
    }
}

@MainActor
final class EcommerceViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var cartItems: [CartItem] = []
    @Published var isLoading = false
    @Published var performanceMetrics = PerformanceMetrics()
    
    private let networkClient: NetworkClient
    private let analytics: EcommerceAnalytics
    
    init() {
        // Configure enterprise networking for e-commerce
        let config = NetworkConfiguration.enterprise
        config.retryPolicy = .exponentialBackoff(maxAttempts: 5)
        config.cachePolicy = .returnCacheDataElseLoad
        config.aiOptimizationEnabled = true
        
        self.networkClient = NetworkClient(configuration: config)
        self.analytics = EcommerceAnalytics()
        
        // Set up authentication
        Task {
            await networkClient.setAuthentication(.bearer("ecommerce-api-token"))
        }
    }
    
    func loadProducts() async {
        isLoading = true
        
        do {
            // Track performance
            let startTime = Date()
            
            // Parallel loading of products and recommendations
            async let productsCall = networkClient.get("/api/products", 
                                                    queryItems: [URLQueryItem(name: "featured", value: "true")],
                                                    as: ProductResponse.self)
            async let recommendationsCall = networkClient.get("/api/recommendations", as: [Product].self)
            
            let (productResponse, recommendations) = try await (productsCall, recommendationsCall)
            
            // Update UI
            self.products = productResponse.products + recommendations
            
            // Track analytics
            let loadTime = Date().timeIntervalSince(startTime)
            await analytics.trackProductsLoaded(count: products.count, loadTime: loadTime)
            
            // Update performance metrics
            await updatePerformanceMetrics()
            
        } catch {
            await analytics.trackError("product_load_failed", error: error)
            print("Failed to load products: \(error)")
        }
        
        isLoading = false
    }
    
    func searchProducts(query: String) async {
        guard !query.isEmpty else { return }
        
        do {
            let searchResponse = try await networkClient.get("/api/search",
                                                           queryItems: [URLQueryItem(name: "q", value: query)],
                                                           as: ProductResponse.self)
            
            self.products = searchResponse.products
            await analytics.trackSearch(query: query, resultsCount: products.count)
            
        } catch {
            await analytics.trackError("search_failed", error: error)
        }
    }
    
    func addToCart(_ product: Product) async {
        let cartItem = CartItem(product: product, quantity: 1)
        cartItems.append(cartItem)
        
        // Sync with backend
        do {
            try await networkClient.post("/api/cart/add",
                                       body: AddToCartRequest(productId: product.id, quantity: 1),
                                       as: CartResponse.self)
            
            await analytics.trackAddToCart(product: product)
            
        } catch {
            // Remove from local cart if backend fails
            cartItems.removeAll { $0.product.id == product.id }
            await analytics.trackError("add_to_cart_failed", error: error)
        }
    }
    
    func checkout() async {
        let checkoutRequest = CheckoutRequest(items: cartItems.map { 
            CheckoutItem(productId: $0.product.id, quantity: $0.quantity) 
        })
        
        do {
            let response = try await networkClient.post("/api/checkout",
                                                      body: checkoutRequest,
                                                      as: CheckoutResponse.self)
            
            // Clear cart on successful checkout
            cartItems.removeAll()
            
            await analytics.trackCheckout(orderId: response.orderId, total: response.total)
            
        } catch {
            await analytics.trackError("checkout_failed", error: error)
        }
    }
    
    private func updatePerformanceMetrics() async {
        let healthStatus = await networkClient.getHealthStatus()
        
        performanceMetrics = PerformanceMetrics(
            averageResponseTime: healthStatus.averageResponseTime,
            successRate: healthStatus.successRate,
            cacheHitRate: healthStatus.cacheHitRate,
            activeConnections: healthStatus.activeConnections
        )
    }
}

// MARK: - Social Media App Example

/// Social media app with real-time feed, messaging, and media sharing
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct SocialMediaExampleView: View {
    @ObservedObject var viewModel: SocialMediaViewModel
    
    var body: some View {
        TabView {
            // Feed Tab
            FeedView(posts: viewModel.posts, onRefresh: {
                await viewModel.refreshFeed()
            })
            .tabItem {
                Image(systemName: "house.fill")
                Text("Feed")
            }
            
            // Messages Tab
            MessagesView(conversations: viewModel.conversations, webSocketStatus: viewModel.webSocketStatus)
            .tabItem {
                Image(systemName: "message.fill")
                Text("Messages")
            }
            
            // Upload Tab
            MediaUploadView { media in
                await viewModel.uploadMedia(media)
            }
            .tabItem {
                Image(systemName: "plus.circle.fill")
                Text("Upload")
            }
        }
        .task {
            await viewModel.initialize()
        }
    }
}

@MainActor
final class SocialMediaViewModel: ObservableObject {
    @Published var posts: [SocialPost] = []
    @Published var conversations: [Conversation] = []
    @Published var webSocketStatus: WebSocketStatus = .disconnected
    
    private let networkClient: NetworkClient
    private var webSocketClient: WebSocketClient?
    private let imageCache = ImageCache()
    
    init() {
        // High-performance configuration for social media
        let config = NetworkConfiguration.enterprise
        config.httpVersion = .http3
        config.connectionPoolSize = 30
        config.compressionEnabled = true
        config.aiOptimizationEnabled = true
        
        self.networkClient = NetworkClient(configuration: config)
    }
    
    func initialize() async {
        // Set up authentication
        await networkClient.setAuthentication(.bearer("social-media-token"))
        
        // Load initial data in parallel
        async let feedTask = loadFeed()
        async let conversationsTask = loadConversations()
        async let webSocketTask = connectWebSocket()
        
        await (feedTask, conversationsTask, webSocketTask)
    }
    
    func loadFeed() async {
        do {
            let feedResponse = try await networkClient.get("/api/feed", as: FeedResponse.self)
            self.posts = feedResponse.posts
            
            // Preload images for better UX
            await preloadImages(for: posts)
            
        } catch {
            print("Failed to load feed: \(error)")
        }
    }
    
    func refreshFeed() async {
        // Use pull-to-refresh optimized loading
        do {
            let lastPostId = posts.first?.id
            let query = lastPostId != nil ? [URLQueryItem(name: "since", value: lastPostId)] : []
            
            let feedResponse = try await networkClient.get("/api/feed", 
                                                         queryItems: query,
                                                         as: FeedResponse.self)
            
            if lastPostId != nil {
                // Prepend new posts
                self.posts = feedResponse.posts + self.posts
            } else {
                self.posts = feedResponse.posts
            }
            
            await preloadImages(for: feedResponse.posts)
            
        } catch {
            print("Failed to refresh feed: \(error)")
        }
    }
    
    func uploadMedia(_ media: MediaUpload) async {
        do {
            // Upload with progress tracking
            let uploadResponse = try await networkClient.upload(
                media.fileURL,
                to: "/api/media/upload",
                as: MediaUploadResponse.self
            )
            
            // Create post with uploaded media
            let post = CreatePostRequest(
                content: media.caption,
                mediaUrls: [uploadResponse.url]
            )
            
            let createdPost = try await networkClient.post("/api/posts",
                                                         body: post,
                                                         as: SocialPost.self)
            
            // Add to feed
            posts.insert(createdPost, at: 0)
            
        } catch {
            print("Failed to upload media: \(error)")
        }
    }
    
    private func connectWebSocket() async {
        guard let wsURL = URL(string: "wss://api.socialmedia.com/ws") else { return }
        
        webSocketClient = WebSocketClient(url: wsURL)
        
        do {
            try await webSocketClient?.connect()
            webSocketStatus = .connected
            
            // Listen for real-time messages
            webSocketClient?.onMessage { [weak self] message in
                Task { @MainActor in
                    await self?.handleWebSocketMessage(message)
                }
            }
            
            webSocketClient?.onStatusChange { [weak self] status in
                Task { @MainActor in
                    self?.webSocketStatus = status
                }
            }
            
        } catch {
            webSocketStatus = .failed(error)
            print("WebSocket connection failed: \(error)")
        }
    }
    
    private func handleWebSocketMessage(_ message: WebSocketMessage) async {
        switch message {
        case .text(let text):
            if let data = text.data(using: .utf8),
               let realTimeEvent = try? JSONDecoder().decode(RealTimeEvent.self, from: data) {
                
                switch realTimeEvent.type {
                case .newMessage:
                    await handleNewMessage(realTimeEvent.data)
                case .postLike:
                    await handlePostLike(realTimeEvent.data)
                case .newFollower:
                    await handleNewFollower(realTimeEvent.data)
                }
            }
        case .data(let data):
            // Handle binary data (e.g., compressed messages)
            break
        }
    }
    
    private func preloadImages(for posts: [SocialPost]) async {
        await withTaskGroup(of: Void.self) { group in
            for post in posts {
                group.addTask {
                    for imageUrl in post.imageUrls {
                        await self.imageCache.preload(url: imageUrl)
                    }
                }
            }
        }
    }
    
    private func loadConversations() async {
        do {
            let conversationsResponse = try await networkClient.get("/api/conversations", 
                                                                  as: ConversationsResponse.self)
            self.conversations = conversationsResponse.conversations
        } catch {
            print("Failed to load conversations: \(error)")
        }
    }
    
    private func handleNewMessage(_ data: [String: Any]) async {
        // Handle real-time message updates
    }
    
    private func handlePostLike(_ data: [String: Any]) async {
        // Handle real-time like updates
    }
    
    private func handleNewFollower(_ data: [String: Any]) async {
        // Handle new follower notifications
    }
}

// MARK: - News Application Example

/// News app with content delivery, offline reading, and personalization
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct NewsAppExampleView: View {
    @ObservedObject var viewModel: NewsAppViewModel
    
    var body: some View {
        NavigationView {
            List {
                Section("Breaking News") {
                    ForEach(viewModel.breakingNews, id: \.id) { article in
                        NewsArticleRowView(article: article) {
                            await viewModel.readArticle(article)
                        }
                    }
                }
                
                Section("Personalized Feed") {
                    ForEach(viewModel.personalizedArticles, id: \.id) { article in
                        NewsArticleRowView(article: article) {
                            await viewModel.readArticle(article)
                        }
                    }
                }
                
                if viewModel.isOfflineMode {
                    Section("Offline Articles") {
                        ForEach(viewModel.offlineArticles, id: \.id) { article in
                            NewsArticleRowView(article: article) {
                                await viewModel.readArticle(article)
                            }
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.refreshNews()
            }
            .navigationTitle("News")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.isOfflineMode ? "Offline" : "Online") {
                        viewModel.toggleOfflineMode()
                    }
                    .foregroundColor(viewModel.isOfflineMode ? .red : .green)
                }
            }
        }
        .task {
            await viewModel.initialize()
        }
    }
}

@MainActor
final class NewsAppViewModel: ObservableObject {
    @Published var breakingNews: [NewsArticle] = []
    @Published var personalizedArticles: [NewsArticle] = []
    @Published var offlineArticles: [NewsArticle] = []
    @Published var isOfflineMode = false
    
    private let networkClient: NetworkClient
    private let offlineManager: OfflineContentManager
    private let personalization: NewsPersonalization
    
    init() {
        // Optimized for content delivery
        let config = NetworkConfiguration.enterprise
        config.cachePolicy = .returnCacheDataElseLoad
        config.cacheSize = 200 * 1024 * 1024 // 200MB for articles
        config.compressionEnabled = true
        config.httpVersion = .http2 // HTTP/2 for better multiplexing
        
        self.networkClient = NetworkClient(configuration: config)
        self.offlineManager = OfflineContentManager()
        self.personalization = NewsPersonalization()
    }
    
    func initialize() async {
        // Check network connectivity
        let isOnline = await NetworkMonitor.shared.isConnected
        isOfflineMode = !isOnline
        
        if isOnline {
            await loadOnlineContent()
        } else {
            await loadOfflineContent()
        }
    }
    
    func refreshNews() async {
        guard !isOfflineMode else { 
            await loadOfflineContent()
            return 
        }
        
        await loadOnlineContent()
    }
    
    private func loadOnlineContent() async {
        await withTaskGroup(of: Void.self) { group in
            // Load breaking news
            group.addTask {
                await self.loadBreakingNews()
            }
            
            // Load personalized content
            group.addTask {
                await self.loadPersonalizedContent()
            }
            
            // Sync offline content
            group.addTask {
                await self.syncOfflineContent()
            }
        }
    }
    
    private func loadBreakingNews() async {
        do {
            let response = try await networkClient.get("/api/news/breaking", as: NewsResponse.self)
            self.breakingNews = response.articles
            
            // Cache breaking news for offline access
            await offlineManager.cache(articles: response.articles, category: .breaking)
            
        } catch {
            print("Failed to load breaking news: \(error)")
            // Fallback to cached content
            self.breakingNews = await offlineManager.getCachedArticles(category: .breaking)
        }
    }
    
    private func loadPersonalizedContent() async {
        do {
            let preferences = await personalization.getUserPreferences()
            let response = try await networkClient.post("/api/news/personalized",
                                                      body: preferences,
                                                      as: NewsResponse.self)
            
            self.personalizedArticles = response.articles
            
            // Update personalization model
            await personalization.updateModel(with: response.articles)
            
            // Cache personalized content
            await offlineManager.cache(articles: response.articles, category: .personalized)
            
        } catch {
            print("Failed to load personalized content: \(error)")
            self.personalizedArticles = await offlineManager.getCachedArticles(category: .personalized)
        }
    }
    
    private func syncOfflineContent() async {
        // Download articles for offline reading
        let articlesToDownload = (breakingNews + personalizedArticles).prefix(20)
        
        await withTaskGroup(of: Void.self) { group in
            for article in articlesToDownload {
                group.addTask {
                    await self.downloadArticleContent(article)
                }
            }
        }
    }
    
    private func downloadArticleContent(_ article: NewsArticle) async {
        do {
            let fullArticle = try await networkClient.get("/api/articles/\(article.id)", 
                                                        as: FullNewsArticle.self)
            
            await offlineManager.storeFullArticle(fullArticle)
            
            // Download and cache images
            for imageUrl in fullArticle.imageUrls {
                await downloadAndCacheImage(url: imageUrl)
            }
            
        } catch {
            print("Failed to download article \(article.id): \(error)")
        }
    }
    
    private func downloadAndCacheImage(url: String) async {
        guard let imageURL = URL(string: url) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            await offlineManager.cacheImage(data: data, url: url)
        } catch {
            print("Failed to cache image: \(error)")
        }
    }
    
    private func loadOfflineContent() async {
        self.breakingNews = await offlineManager.getCachedArticles(category: .breaking)
        self.personalizedArticles = await offlineManager.getCachedArticles(category: .personalized)
        self.offlineArticles = await offlineManager.getAllOfflineArticles()
    }
    
    func readArticle(_ article: NewsArticle) async {
        // Track reading behavior for personalization
        await personalization.trackArticleRead(article)
        
        // Mark as read
        await offlineManager.markAsRead(articleId: article.id)
    }
    
    func toggleOfflineMode() {
        isOfflineMode.toggle()
        
        Task {
            if isOfflineMode {
                await loadOfflineContent()
            } else {
                await loadOnlineContent()
            }
        }
    }
}

// MARK: - Financial Trading App Example

/// High-frequency trading app with real-time market data and low-latency execution
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct FinanceAppExampleView: View {
    @ObservedObject var viewModel: FinanceAppViewModel
    
    var body: some View {
        TabView {
            // Market Data Tab
            MarketDataView(viewModel: viewModel)
            .tabItem {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("Markets")
            }
            
            // Portfolio Tab
            PortfolioView(portfolio: viewModel.portfolio, performance: viewModel.performanceMetrics)
            .tabItem {
                Image(systemName: "briefcase.fill")
                Text("Portfolio")
            }
            
            // Trading Tab
            TradingView(watchlist: viewModel.watchlist) { order in
                await viewModel.executeOrder(order)
            }
            .tabItem {
                Image(systemName: "dollarsign.circle.fill")
                Text("Trade")
            }
        }
        .task {
            await viewModel.initialize()
        }
    }
}

@MainActor
final class FinanceAppViewModel: ObservableObject {
    @Published var marketData: [MarketQuote] = []
    @Published var portfolio: Portfolio = Portfolio.empty
    @Published var watchlist: [String] = ["AAPL", "GOOGL", "MSFT", "TSLA"]
    @Published var performanceMetrics = TradingPerformanceMetrics()
    
    private let networkClient: NetworkClient
    private var webSocketClient: WebSocketClient?
    private let orderExecutor: OrderExecutor
    
    init() {
        // Ultra-low latency configuration for trading
        let config = NetworkConfiguration.enterprise
        config.httpVersion = .http3
        config.timeout = 5 // Very short timeout for trading
        config.retryPolicy = .none // No retries for trading
        config.connectionPoolSize = 50
        config.aiOptimizationEnabled = true
        
        self.networkClient = NetworkClient(configuration: config)
        self.orderExecutor = OrderExecutor(networkClient: networkClient)
    }
    
    func initialize() async {
        // Set up secure authentication for trading
        await networkClient.setAuthentication(.custom { request in
            var modifiedRequest = request
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let signature = self.generateSignature(for: request, timestamp: timestamp)
            
            modifiedRequest.setValue("trading-api-key", forHTTPHeaderField: "X-API-Key")
            modifiedRequest.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
            modifiedRequest.setValue(signature, forHTTPHeaderField: "X-Signature")
            
            return modifiedRequest
        })
        
        // Initialize in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadMarketData() }
            group.addTask { await self.loadPortfolio() }
            group.addTask { await self.connectToRealTimeData() }
        }
    }
    
    private func loadMarketData() async {
        do {
            let response = try await networkClient.get("/api/market/quotes",
                                                     queryItems: watchlist.map { URLQueryItem(name: "symbols", value: $0) },
                                                     as: MarketDataResponse.self)
            
            self.marketData = response.quotes
            
        } catch {
            print("Failed to load market data: \(error)")
        }
    }
    
    private func loadPortfolio() async {
        do {
            let portfolio = try await networkClient.get("/api/portfolio", as: Portfolio.self)
            self.portfolio = portfolio
            
            // Calculate performance metrics
            await updatePerformanceMetrics()
            
        } catch {
            print("Failed to load portfolio: \(error)")
        }
    }
    
    private func connectToRealTimeData() async {
        guard let wsURL = URL(string: "wss://api.trading.com/realtime") else { return }
        
        webSocketClient = WebSocketClient(url: wsURL)
        
        do {
            try await webSocketClient?.connect()
            
            // Subscribe to watchlist symbols
            let subscription = MarketDataSubscription(symbols: watchlist)
            let subscriptionData = try JSONEncoder().encode(subscription)
            
            try await webSocketClient?.send(data: subscriptionData)
            
            // Handle real-time price updates
            webSocketClient?.onMessage { [weak self] message in
                Task { @MainActor in
                    await self?.handleMarketDataUpdate(message)
                }
            }
            
        } catch {
            print("Failed to connect to real-time data: \(error)")
        }
    }
    
    private func handleMarketDataUpdate(_ message: WebSocketMessage) async {
        switch message {
        case .data(let data):
            if let update = try? JSONDecoder().decode(MarketDataUpdate.self, from: data) {
                // Update market data with sub-millisecond latency
                if let index = marketData.firstIndex(where: { $0.symbol == update.symbol }) {
                    marketData[index].price = update.price
                    marketData[index].change = update.change
                    marketData[index].timestamp = update.timestamp
                }
                
                // Update portfolio if we hold this symbol
                await updatePortfolioValue(for: update.symbol, price: update.price)
            }
        case .text(let text):
            // Handle text-based market data
            break
        }
    }
    
    func executeOrder(_ order: TradingOrder) async {
        do {
            let startTime = Date()
            
            // Execute order with ultra-low latency
            let executionResult = try await orderExecutor.execute(order)
            
            let executionTime = Date().timeIntervalSince(startTime)
            
            // Update portfolio
            await updatePortfolioWithExecution(executionResult)
            
            // Track performance
            performanceMetrics.recordExecution(
                latency: executionTime,
                success: executionResult.status == .filled
            )
            
        } catch {
            print("Order execution failed: \(error)")
            performanceMetrics.recordExecutionFailure()
        }
    }
    
    private func updatePortfolioValue(for symbol: String, price: Double) async {
        if let position = portfolio.positions.first(where: { $0.symbol == symbol }) {
            let oldValue = position.quantity * position.averagePrice
            let newValue = position.quantity * price
            let unrealizedPnL = newValue - oldValue
            
            // Update portfolio value
            portfolio.totalValue += unrealizedPnL
            portfolio.unrealizedPnL += unrealizedPnL
        }
    }
    
    private func updatePortfolioWithExecution(_ execution: OrderExecution) async {
        // Update positions based on execution
        if let existingPosition = portfolio.positions.first(where: { $0.symbol == execution.symbol }) {
            // Update existing position
            let newQuantity = existingPosition.quantity + execution.quantity
            let newValue = (existingPosition.averagePrice * existingPosition.quantity) + 
                          (execution.price * execution.quantity)
            let newAveragePrice = newValue / newQuantity
            
            existingPosition.quantity = newQuantity
            existingPosition.averagePrice = newAveragePrice
        } else {
            // Create new position
            let newPosition = Position(
                symbol: execution.symbol,
                quantity: execution.quantity,
                averagePrice: execution.price
            )
            portfolio.positions.append(newPosition)
        }
    }
    
    private func updatePerformanceMetrics() async {
        let healthStatus = await networkClient.getHealthStatus()
        
        performanceMetrics.networkLatency = healthStatus.averageResponseTime
        performanceMetrics.successRate = healthStatus.successRate
        performanceMetrics.updateTimestamp = Date()
    }
    
    private func generateSignature(for request: URLRequest, timestamp: String) -> String {
        // Implement HMAC-SHA256 signature for secure trading API
        let message = "\(request.httpMethod ?? "GET")\(request.url?.path ?? "")\(timestamp)"
        // Return computed signature
        return "computed_signature"
    }
}

// MARK: - Enterprise Integration Example

/// Multi-tenant SaaS platform with enterprise-grade features
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct EnterpriseExampleView: View {
    @StateObject private var viewModel = EnterpriseViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Security Status
            SecurityStatusView(status: viewModel.securityStatus)
            
            // Multi-tenant Dashboard
            TenantDashboardView(tenants: viewModel.tenants)
            
            // Enterprise Metrics
            EnterpriseMetricsView(metrics: viewModel.enterpriseMetrics)
            
            // AI Insights
            AIInsightsView(insights: viewModel.aiInsights)
        }
        .padding()
        .navigationTitle("Enterprise Platform")
        .task {
            await viewModel.initialize()
        }
    }
}

@MainActor
final class EnterpriseViewModel: ObservableObject {
    @Published var securityStatus = SecurityStatus.unknown
    @Published var tenants: [Tenant] = []
    @Published var enterpriseMetrics = EnterpriseMetrics()
    @Published var aiInsights: [AIInsight] = []
    
    private let networkClient: NetworkClient
    private let securityManager: EnterpriseSecurityManager
    private let aiIntelligence: NetworkIntelligence
    
    init() {
        // Maximum enterprise configuration
        let config = NetworkConfiguration.enterprise
        config.security = .enterprise
        config.encryption = .endToEnd
        config.certificatePinning = .enabled(certificates: Self.enterpriseCertificates)
        config.aiOptimizationEnabled = true
        config.observabilityEnabled = true
        config.metricsCollectionEnabled = true
        
        self.networkClient = NetworkClient(configuration: config)
        self.securityManager = EnterpriseSecurityManager()
        self.aiIntelligence = NetworkIntelligence()
    }
    
    func initialize() async {
        // Enterprise initialization sequence
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.initializeSecurity() }
            group.addTask { await self.loadTenants() }
            group.addTask { await self.startMetricsCollection() }
            group.addTask { await self.enableAIMonitoring() }
        }
    }
    
    private func initializeSecurity() async {
        do {
            // Zero-trust security initialization
            let securityStatus = try await securityManager.initializeZeroTrust()
            self.securityStatus = securityStatus
            
            // Enable threat monitoring
            await securityManager.enableThreatMonitoring()
            
        } catch {
            print("Security initialization failed: \(error)")
            securityStatus = .compromised
        }
    }
    
    private func loadTenants() async {
        do {
            let response = try await networkClient.get("/api/enterprise/tenants", as: TenantsResponse.self)
            self.tenants = response.tenants
            
            // Load tenant-specific metrics
            for tenant in tenants {
                await loadTenantMetrics(tenant)
            }
            
        } catch {
            print("Failed to load tenants: \(error)")
        }
    }
    
    private func loadTenantMetrics(_ tenant: Tenant) async {
        do {
            let metrics = try await networkClient.get("/api/enterprise/tenants/\(tenant.id)/metrics",
                                                    as: TenantMetrics.self)
            
            // Update tenant with metrics
            if let index = tenants.firstIndex(where: { $0.id == tenant.id }) {
                tenants[index].metrics = metrics
            }
            
        } catch {
            print("Failed to load metrics for tenant \(tenant.id): \(error)")
        }
    }
    
    private func startMetricsCollection() async {
        // Enterprise observability
        let observability = await networkClient.enterpriseObservability
        await observability.enableMetricsCollection()
        
        // Periodic metrics update
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task {
                await self.updateEnterpriseMetrics()
            }
        }
    }
    
    private func updateEnterpriseMetrics() async {
        let healthStatus = await networkClient.getHealthStatus()
        let securityMetrics = await securityManager.getSecurityMetrics()
        
        enterpriseMetrics = EnterpriseMetrics(
            totalRequests: healthStatus.totalRequests,
            averageLatency: healthStatus.averageResponseTime,
            successRate: healthStatus.successRate,
            securityScore: securityMetrics.overallScore,
            threatLevel: securityMetrics.threatLevel,
            complianceScore: securityMetrics.complianceScore
        )
    }
    
    private func enableAIMonitoring() async {
        await aiIntelligence.setOptimizationLevel(.enterprise)
        
        // Generate AI insights periodically
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await self.generateAIInsights()
            }
        }
    }
    
    private func generateAIInsights() async {
        let insights = await aiIntelligence.generateInsights()
        self.aiInsights = insights.map { insight in
            AIInsight(
                title: insight.title,
                description: insight.description,
                confidence: insight.confidence,
                actionable: insight.actionable,
                impact: insight.impact
            )
        }
    }
    
    private static let enterpriseCertificates: [SecCertificate] = {
        // Load enterprise certificates
        return []
    }()
}

// MARK: - Supporting Views and Models

struct PerformanceMetricsView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Metrics")
                .font(.headline)
            
            HStack {
                MetricView(title: "Response Time", value: "\(Int(metrics.averageResponseTime))ms")
                MetricView(title: "Success Rate", value: "\(Int(metrics.successRate * 100))%")
                MetricView(title: "Cache Hit", value: "\(Int(metrics.cacheHitRate * 100))%")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MetricView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Data Models

struct Product: Codable, Identifiable {
    let id: String
    let name: String
    let price: Double
    let imageUrl: String
    let description: String
}

struct ProductResponse: Codable {
    let products: [Product]
    let totalCount: Int
}

struct CartItem: Identifiable {
    let id = UUID()
    let product: Product
    let quantity: Int
}

struct PerformanceMetrics {
    var averageResponseTime: TimeInterval = 0
    var successRate: Double = 0
    var cacheHitRate: Double = 0
    var activeConnections: Int = 0
}

struct SocialPost: Codable, Identifiable {
    let id: String
    let content: String
    let imageUrls: [String]
    let authorId: String
    let timestamp: Date
    let likes: Int
    let comments: Int
}

struct NewsArticle: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let imageUrl: String
    let publishedAt: Date
    let category: String
}

struct MarketQuote: Codable, Identifiable {
    let id = UUID()
    let symbol: String
    var price: Double
    var change: Double
    var timestamp: Date
}

struct Portfolio: Codable {
    var positions: [Position]
    var totalValue: Double
    var unrealizedPnL: Double
    
    static let empty = Portfolio(positions: [], totalValue: 0, unrealizedPnL: 0)
}

struct Position: Codable, Identifiable {
    let id = UUID()
    let symbol: String
    var quantity: Double
    var averagePrice: Double
}

struct TradingPerformanceMetrics {
    var networkLatency: TimeInterval = 0
    var successRate: Double = 0
    var executionCount: Int = 0
    var failureCount: Int = 0
    var updateTimestamp = Date()
    
    mutating func recordExecution(latency: TimeInterval, success: Bool) {
        networkLatency = (networkLatency * Double(executionCount) + latency) / Double(executionCount + 1)
        
        if success {
            executionCount += 1
        } else {
            failureCount += 1
        }
        
        successRate = Double(executionCount) / Double(executionCount + failureCount)
        updateTimestamp = Date()
    }
    
    mutating func recordExecutionFailure() {
        failureCount += 1
        successRate = Double(executionCount) / Double(executionCount + failureCount)
        updateTimestamp = Date()
    }
}

// Additional models and implementations...
// [Rest of the supporting types and helper classes would continue here]

#Preview {
    RealWorldExamplesView()
}