using System.Net;
using System.Text;
using System.Text.Json;
using ZSDU.Backend;

/// <summary>
/// ZSDU Backend - Single Windows Console Application
///
/// Architecture:
/// ┌─────────────────────────────────────────┐
/// │ ZSDU.Backend.exe (Windows Server 2022)  │
/// │  ├─ HTTP API (:8080) - matchmaking      │
/// │  ├─ TCP Traversal (:7777)               │
/// │  ├─ ServerOrchestrator - process mgmt   │
/// │  ├─ SessionRegistry - in-memory         │
/// │  └─ GameService - in-process            │
/// └─────────────────────────────────────────┘
///           │
///           ├─→ godot_server.exe (port 27015)
///           ├─→ godot_server.exe (port 27016)
///           └─→ godot_server.exe (port 27017)
/// </summary>
class Program
{
    private static readonly CancellationTokenSource Cts = new();

    static async Task Main(string[] args)
    {
        Console.WriteLine("╔═══════════════════════════════════════════╗");
        Console.WriteLine("║     ZSDU Backend - Windows Server 2022    ║");
        Console.WriteLine("╚═══════════════════════════════════════════╝");
        Console.WriteLine();

        // Load config
        var config = Config.Load();
        Console.WriteLine($"HTTP Port: {config.HttpPort}");
        Console.WriteLine($"Traversal Port: {config.TraversalPort}");
        Console.WriteLine($"Game Server Ports: {config.BaseGamePort}-{config.BaseGamePort + config.MaxServers - 1}");
        Console.WriteLine($"Godot Server Path: {config.GodotServerPath}");
        Console.WriteLine();

        // Handle Ctrl+C
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            Console.WriteLine("\nShutting down...");
            Cts.Cancel();
        };

        // Initialize services (all in-process)
        var sessionRegistry = new SessionRegistry();
        var orchestrator = new ServerOrchestrator(config, sessionRegistry);
        var gameService = new GameService(sessionRegistry);
        var httpApi = new HttpApi(config, sessionRegistry, orchestrator, gameService);
        var traversal = new TraversalServer(config, sessionRegistry);

        try
        {
            // Start services
            var tasks = new List<Task>
            {
                httpApi.StartAsync(Cts.Token),
                traversal.StartAsync(Cts.Token),
                orchestrator.StartAsync(Cts.Token)
            };

            Console.WriteLine("═══════════════════════════════════════════");
            Console.WriteLine("  Backend running. Press Ctrl+C to stop.");
            Console.WriteLine("═══════════════════════════════════════════");
            Console.WriteLine();
            Console.WriteLine("Endpoints:");
            Console.WriteLine($"  HTTP API:    http://localhost:{config.HttpPort}/");
            Console.WriteLine($"  Traversal:   tcp://localhost:{config.TraversalPort}/");
            Console.WriteLine();
            Console.WriteLine("API Routes:");
            Console.WriteLine("  GET  /health              - Health check");
            Console.WriteLine("  GET  /status              - Server status");
            Console.WriteLine("  GET  /servers             - List game servers");
            Console.WriteLine("  POST /servers/ready       - Server reports ready");
            Console.WriteLine("  POST /servers/heartbeat   - Server heartbeat");
            Console.WriteLine("  POST /match/find          - Find/create match");
            Console.WriteLine("  GET  /match/{id}          - Get match status");
            Console.WriteLine();

            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException)
        {
            // Expected on shutdown
        }
        finally
        {
            orchestrator.ShutdownAll();
        }

        Console.WriteLine("Backend stopped.");
    }
}

// ============================================
// CONFIGURATION
// ============================================

public class Config
{
    public int HttpPort { get; set; } = 8080;
    public int TraversalPort { get; set; } = 7777;
    public int BaseGamePort { get; set; } = 27015;
    public int MaxServers { get; set; } = 10;
    public int PlayersPerServer { get; set; } = 32;
    public string GodotServerPath { get; set; } = "godot_server.exe";
    public string GodotProjectPath { get; set; } = "";
    public int MinReadyServers { get; set; } = 1;

    // Public host address that clients connect to (single source of truth)
    public string PublicHost { get; set; } = "162.248.94.149";

    // ============================================
    // LOCKED HEARTBEAT CONSTANTS (match Godot side)
    // ============================================
    // Godot sends heartbeat every 2 seconds
    // Backend marks server dead after 6 seconds (3 missed heartbeats)
    public const int HeartbeatIntervalSeconds = 2;   // DO NOT CHANGE
    public const int HeartbeatTimeoutSeconds = 6;    // DO NOT CHANGE

    public static Config Load()
    {
        var config = new Config();

        // Load from environment
        if (int.TryParse(Environment.GetEnvironmentVariable("HTTP_PORT"), out var httpPort))
            config.HttpPort = httpPort;
        if (int.TryParse(Environment.GetEnvironmentVariable("TRAVERSAL_PORT"), out var travPort))
            config.TraversalPort = travPort;
        if (int.TryParse(Environment.GetEnvironmentVariable("BASE_GAME_PORT"), out var gamePort))
            config.BaseGamePort = gamePort;
        if (int.TryParse(Environment.GetEnvironmentVariable("MAX_SERVERS"), out var maxServers))
            config.MaxServers = maxServers;

        var godotPath = Environment.GetEnvironmentVariable("GODOT_SERVER_PATH");
        if (!string.IsNullOrEmpty(godotPath))
            config.GodotServerPath = godotPath;

        var projectPath = Environment.GetEnvironmentVariable("GODOT_PROJECT_PATH");
        if (!string.IsNullOrEmpty(projectPath))
            config.GodotProjectPath = projectPath;

        var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST");
        if (!string.IsNullOrEmpty(publicHost))
            config.PublicHost = publicHost;

        return config;
    }
}
