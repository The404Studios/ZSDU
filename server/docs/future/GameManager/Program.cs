using GameManager;
using GameManager.Data;
using GameManager.Events;
using GameManager.Network;
using GameManager.Services;

/// <summary>
/// ZSDU Game Manager - Main Entry Point
///
/// Architecture (matching Kubernetes diagram):
/// ┌─────────────────────────────────────────────────────────────┐
/// │                    Game Manager Pod                          │
/// │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
/// │  │  WebSocket  │  │ HTTP API    │  │  TCP        │          │
/// │  │  Server     │  │ Server      │  │  Traversal  │          │
/// │  └─────────────┘  └─────────────┘  └─────────────┘          │
/// │        │                │                │                   │
/// │  ┌─────────────────────────────────────────────────────┐    │
/// │  │              Service Layer                           │    │
/// │  │  ┌──────────────┐ ┌────────────┐ ┌───────────┐       │    │
/// │  │  │SessionManager│ │ Matchmaker │ │  Director │       │    │
/// │  │  └──────────────┘ └────────────┘ └───────────┘       │    │
/// │  └─────────────────────────────────────────────────────┘    │
/// │        │                                                     │
/// │  ┌─────────────────────────────────────────────────────┐    │
/// │  │              Event Broker                            │    │
/// │  └─────────────────────────────────────────────────────┘    │
/// │        │                                                     │
/// │  ┌─────────────────────────────────────────────────────┐    │
/// │  │         Data Layer (Cache + Database)                │    │
/// │  └─────────────────────────────────────────────────────┘    │
/// └─────────────────────────────────────────────────────────────┘
/// </summary>
class Program
{
    private static readonly CancellationTokenSource _cts = new();

    static async Task Main(string[] args)
    {
        Console.WriteLine("╔═══════════════════════════════════════════════════════════╗");
        Console.WriteLine("║           ZSDU Game Manager v1.0                          ║");
        Console.WriteLine("║   Session Management | Matchmaking | Orchestration        ║");
        Console.WriteLine("╚═══════════════════════════════════════════════════════════╝");
        Console.WriteLine();

        // Load configuration
        var config = Configuration.FromEnvironment();
        PrintConfiguration(config);

        // Handle Ctrl+C gracefully
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            Console.WriteLine("\n[Main] Shutdown requested...");
            _cts.Cancel();
        };

        try
        {
            // Initialize services
            Console.WriteLine("[Main] Initializing services...");

            // Data Layer
            var cache = new CacheService();
            var database = new DatabaseService();

            // Event Broker
            var eventBroker = new EventBroker();
            var eventLogger = new EventLogger();
            eventBroker.SubscribeAll(eventLogger.HandleEvent);
            eventBroker.Start();

            // Service Layer
            var sessionManager = new SessionManager(eventBroker, config);
            var matchmaker = new Matchmaker(sessionManager, eventBroker, config);
            var director = new Director(sessionManager, eventBroker, config);

            // Network Layer
            var httpServer = new HttpApiServer(sessionManager, matchmaker, director, config);
            var wsServer = new WebSocketServer(eventBroker, sessionManager, matchmaker, config);

            Console.WriteLine("[Main] Starting servers...\n");

            // Start all services
            var tasks = new List<Task>
            {
                Task.Run(() => httpServer.StartAsync(_cts.Token)),
                Task.Run(() => wsServer.StartAsync(_cts.Token)),
                director.InitializeAsync()
            };

            // Also start legacy TCP traversal server for backwards compatibility
            var traversalServer = new TraversalServer.Server(config.TraversalPort);
            tasks.Add(Task.Run(() => traversalServer.RunAsync(_cts.Token)));

            Console.WriteLine();
            Console.WriteLine("═══════════════════════════════════════════════════════════");
            Console.WriteLine("  Services running. Press Ctrl+C to stop.");
            Console.WriteLine("═══════════════════════════════════════════════════════════");
            Console.WriteLine();
            Console.WriteLine("Endpoints:");
            Console.WriteLine($"  HTTP API:    http://localhost:{config.HttpPort}/");
            Console.WriteLine($"  WebSocket:   ws://localhost:{config.WebSocketPort}/");
            Console.WriteLine($"  Traversal:   tcp://localhost:{config.TraversalPort}/");
            Console.WriteLine();
            Console.WriteLine("API Routes:");
            Console.WriteLine("  GET  /health               - Health check");
            Console.WriteLine("  GET  /status               - Server status");
            Console.WriteLine("  GET  /api/servers          - List game servers");
            Console.WriteLine("  POST /api/servers          - Register server");
            Console.WriteLine("  POST /api/servers/heartbeat - Server heartbeat");
            Console.WriteLine("  POST /api/sessions         - Create player session");
            Console.WriteLine("  POST /api/matchmaking      - Start matchmaking");
            Console.WriteLine("  GET  /api/matchmaking/{id} - Check matchmaking status");
            Console.WriteLine("  GET  /api/scaling/status   - Get scaling status");
            Console.WriteLine();

            // Wait for cancellation
            await Task.WhenAny(tasks);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Main] Fatal error: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            Environment.Exit(1);
        }

        Console.WriteLine("[Main] Server stopped.");
    }

    private static void PrintConfiguration(Configuration config)
    {
        Console.WriteLine("Configuration:");
        Console.WriteLine($"  HTTP Port:        {config.HttpPort}");
        Console.WriteLine($"  WebSocket Port:   {config.WebSocketPort}");
        Console.WriteLine($"  Traversal Port:   {config.TraversalPort}");
        Console.WriteLine($"  Min Servers:      {config.MinGameServers}");
        Console.WriteLine($"  Max Servers:      {config.MaxGameServers}");
        Console.WriteLine($"  Players/Server:   {config.PlayersPerServer}");
        Console.WriteLine($"  Kubernetes:       {config.RunInKubernetes}");
        Console.WriteLine();
    }
}
