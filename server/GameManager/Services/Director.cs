using System.Diagnostics;
using GameManager.Data;
using GameManager.Events;

namespace GameManager.Services;

/// <summary>
/// Director - orchestrates game server instances
/// Handles scaling, spawning new servers, and health management
/// In Kubernetes, this would interact with the K8s API
/// </summary>
public class Director
{
    private readonly SessionManager _sessionManager;
    private readonly EventBroker _eventBroker;
    private readonly Configuration _config;
    private readonly Timer _monitorTimer;
    private readonly List<Process> _localProcesses = new();

    // Scaling thresholds
    private const float SCALE_UP_THRESHOLD = 0.8f;   // Scale up when 80% capacity
    private const float SCALE_DOWN_THRESHOLD = 0.3f; // Scale down when 30% capacity
    private const int SCALE_COOLDOWN_SECONDS = 60;

    private DateTime _lastScaleAction = DateTime.MinValue;

    public Director(SessionManager sessionManager, EventBroker eventBroker, Configuration config)
    {
        _sessionManager = sessionManager;
        _eventBroker = eventBroker;
        _config = config;

        // Monitor every 30 seconds
        _monitorTimer = new Timer(
            _ => MonitorAndScale(),
            null,
            TimeSpan.FromSeconds(30),
            TimeSpan.FromSeconds(30));

        // Subscribe to events
        _eventBroker.Subscribe<ServerUnregisteredEvent>(OnServerUnregistered);
        _eventBroker.Subscribe<MatchFoundEvent>(OnMatchFound);
    }

    /// <summary>
    /// Initialize director - ensure minimum servers are running
    /// </summary>
    public async Task InitializeAsync()
    {
        Console.WriteLine($"[Director] Initializing with min {_config.MinGameServers} servers");

        var currentCount = _sessionManager.GetAllServers().Count();

        while (currentCount < _config.MinGameServers)
        {
            await SpawnGameServerAsync();
            currentCount++;
        }
    }

    /// <summary>
    /// Spawn a new game server instance
    /// </summary>
    public async Task<string?> SpawnGameServerAsync(string? gameMode = null, string? mapName = null)
    {
        var serverCount = _sessionManager.GetAllServers().Count();
        if (serverCount >= _config.MaxGameServers)
        {
            Console.WriteLine($"[Director] Cannot spawn: max servers ({_config.MaxGameServers}) reached");
            return null;
        }

        var serverId = Guid.NewGuid().ToString();
        var port = _config.GameServerBasePort + serverCount;

        if (_config.RunInKubernetes)
        {
            return await SpawnKubernetesServerAsync(serverId, port, gameMode, mapName);
        }
        else
        {
            return await SpawnLocalServerAsync(serverId, port, gameMode, mapName);
        }
    }

    /// <summary>
    /// Spawn a local game server process (for development)
    /// </summary>
    private async Task<string?> SpawnLocalServerAsync(string serverId, int port, string? gameMode, string? mapName)
    {
        try
        {
            // In a real setup, this would launch the Godot server
            // For now, we'll just register a placeholder
            Console.WriteLine($"[Director] Spawning local server on port {port}");

            // The game server would register itself via the HTTP API
            // For development, we can simulate this
            var registration = new ServerRegistration
            {
                Name = $"Server-{serverId[..8]}",
                Port = port,
                MaxPlayers = _config.PlayersPerServer,
                GameMode = gameMode ?? "survival",
                MapName = mapName ?? "default",
                Version = "1.0"
            };

            var server = await _sessionManager.RegisterServerAsync(registration, "127.0.0.1");
            return server.Id;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Director] Failed to spawn local server: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Spawn a Kubernetes-managed game server
    /// </summary>
    private async Task<string?> SpawnKubernetesServerAsync(string serverId, int port, string? gameMode, string? mapName)
    {
        try
        {
            Console.WriteLine($"[Director] Spawning Kubernetes pod for server {serverId}");

            // In production, this would use the Kubernetes API
            // kubectl create deployment, or use the C# Kubernetes client
            var podName = $"gameserver-{serverId[..8]}";

            // Example: Using kubectl (would use K8s client library in production)
            var args = $"run {podName} " +
                       $"--image={_config.GameServerImage} " +
                       $"--namespace={_config.K8sNamespace} " +
                       $"--port={port} " +
                       $"--env=SERVER_ID={serverId} " +
                       $"--env=GAME_MODE={gameMode ?? "survival"} " +
                       $"--env=MAP_NAME={mapName ?? "default"} " +
                       $"--env=MANAGER_HOST=game-manager.{_config.K8sNamespace}.svc.cluster.local";

            Console.WriteLine($"[Director] K8s command: kubectl {args}");

            // Would actually execute this
            // await ExecuteKubectlAsync(args);

            return serverId;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Director] Failed to spawn K8s server: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Terminate a game server
    /// </summary>
    public async Task TerminateServerAsync(string serverId, string reason = "")
    {
        var server = _sessionManager.GetServer(serverId);
        if (server == null)
            return;

        Console.WriteLine($"[Director] Terminating server {server.Name}: {reason}");

        if (_config.RunInKubernetes && server.PodName != null)
        {
            // Delete Kubernetes pod
            // await ExecuteKubectlAsync($"delete pod {server.PodName} --namespace={_config.K8sNamespace}");
        }

        await _sessionManager.UnregisterServerAsync(serverId, reason);
    }

    /// <summary>
    /// Monitor capacity and scale accordingly
    /// </summary>
    private void MonitorAndScale()
    {
        try
        {
            var servers = _sessionManager.GetAllServers().ToList();
            if (servers.Count == 0)
            {
                // No servers, spawn minimum
                _ = SpawnGameServerAsync();
                return;
            }

            // Check cooldown
            if ((DateTime.UtcNow - _lastScaleAction).TotalSeconds < SCALE_COOLDOWN_SECONDS)
                return;

            // Calculate capacity
            var totalCapacity = servers.Sum(s => s.MaxPlayers);
            var totalPlayers = servers.Sum(s => s.CurrentPlayers);
            var utilization = totalCapacity > 0 ? (float)totalPlayers / totalCapacity : 0;

            // Check available capacity (servers that can accept new players)
            var availableSlots = servers.Where(s => s.IsAvailable).Sum(s => s.MaxPlayers - s.CurrentPlayers);

            Console.WriteLine($"[Director] Status: {servers.Count} servers, {totalPlayers}/{totalCapacity} players ({utilization:P0}), {availableSlots} available slots");

            // Scale up if needed
            if (utilization > SCALE_UP_THRESHOLD || availableSlots < _config.PlayersPerServer)
            {
                if (servers.Count < _config.MaxGameServers)
                {
                    Console.WriteLine($"[Director] Scaling up (utilization: {utilization:P0})");
                    _ = SpawnGameServerAsync();
                    _lastScaleAction = DateTime.UtcNow;

                    _ = _eventBroker.PublishAsync(new ScaleUpRequestedEvent
                    {
                        RequestedCount = 1,
                        Reason = $"High utilization: {utilization:P0}"
                    });
                }
            }
            // Scale down if over-provisioned
            else if (utilization < SCALE_DOWN_THRESHOLD && servers.Count > _config.MinGameServers)
            {
                // Find empty server to terminate
                var emptyServer = servers.FirstOrDefault(s => s.CurrentPlayers == 0 && s.Status == ServerStatus.Ready);
                if (emptyServer != null)
                {
                    Console.WriteLine($"[Director] Scaling down (utilization: {utilization:P0})");
                    _ = TerminateServerAsync(emptyServer.Id, "scale_down");
                    _lastScaleAction = DateTime.UtcNow;

                    _ = _eventBroker.PublishAsync(new ScaleDownRequestedEvent
                    {
                        RequestedCount = 1,
                        ServerIds = new List<string> { emptyServer.Id }
                    });
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Director] Monitor error: {ex.Message}");
        }
    }

    /// <summary>
    /// Handle server unregistration - may need to spawn replacement
    /// </summary>
    private async Task OnServerUnregistered(ServerUnregisteredEvent evt)
    {
        var serverCount = _sessionManager.GetAllServers().Count();
        if (serverCount < _config.MinGameServers)
        {
            Console.WriteLine($"[Director] Server count below minimum, spawning replacement");
            await SpawnGameServerAsync();
        }
    }

    /// <summary>
    /// Handle match found - ensure server is ready
    /// </summary>
    private Task OnMatchFound(MatchFoundEvent evt)
    {
        var server = _sessionManager.GetServer(evt.ServerId);
        if (server != null)
        {
            Console.WriteLine($"[Director] Match assigned to {server.Name}, {evt.PlayerIds.Count} players");
        }
        return Task.CompletedTask;
    }

    /// <summary>
    /// Get current scaling status
    /// </summary>
    public ScalingStatus GetStatus()
    {
        var servers = _sessionManager.GetAllServers().ToList();
        return new ScalingStatus
        {
            TotalServers = servers.Count,
            MinServers = _config.MinGameServers,
            MaxServers = _config.MaxGameServers,
            TotalCapacity = servers.Sum(s => s.MaxPlayers),
            CurrentPlayers = servers.Sum(s => s.CurrentPlayers),
            AvailableSlots = servers.Where(s => s.IsAvailable).Sum(s => s.MaxPlayers - s.CurrentPlayers)
        };
    }
}

public class ScalingStatus
{
    public int TotalServers { get; set; }
    public int MinServers { get; set; }
    public int MaxServers { get; set; }
    public int TotalCapacity { get; set; }
    public int CurrentPlayers { get; set; }
    public int AvailableSlots { get; set; }
    public float Utilization => TotalCapacity > 0 ? (float)CurrentPlayers / TotalCapacity : 0;
}
