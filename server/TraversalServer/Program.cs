using System;
using System.Net;
using System.Threading;
using System.Threading.Tasks;

namespace TraversalServer;

/// <summary>
/// ZSDU Traversal Server - Session Discovery and NAT Traversal
///
/// This server handles:
/// - Session registration (hosts announce themselves)
/// - Session discovery (clients query available games)
/// - Heartbeat keepalive (removes stale sessions)
/// - Basic NAT traversal coordination
/// </summary>
class Program
{
    private static readonly CancellationTokenSource _cts = new();

    static async Task Main(string[] args)
    {
        Console.WriteLine("========================================");
        Console.WriteLine("  ZSDU Traversal Server v1.0");
        Console.WriteLine("========================================");
        Console.WriteLine();

        // Parse command line args
        int port = 7777;
        if (args.Length > 0 && int.TryParse(args[0], out int parsedPort))
        {
            port = parsedPort;
        }

        // Handle Ctrl+C gracefully
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            Console.WriteLine("\nShutdown requested...");
            _cts.Cancel();
        };

        try
        {
            var server = new Server(port);

            Console.WriteLine($"Starting server on port {port}...");
            Console.WriteLine("Press Ctrl+C to stop.");
            Console.WriteLine();

            await server.RunAsync(_cts.Token);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Fatal error: {ex.Message}");
            Environment.Exit(1);
        }

        Console.WriteLine("Server stopped.");
    }
}
