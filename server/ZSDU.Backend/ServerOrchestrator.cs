using System.Diagnostics;

namespace ZSDU.Backend;

/// <summary>
/// Manages Godot game server processes
/// Spawns, monitors, and terminates godot_server.exe instances
/// </summary>
public class ServerOrchestrator
{
    private readonly Config _config;
    private readonly SessionRegistry _registry;
    private readonly Dictionary<string, Process> _processes = new();
    private readonly HashSet<int> _usedPorts = new();
    private readonly object _lock = new();

    public ServerOrchestrator(Config config, SessionRegistry registry)
    {
        _config = config;
        _registry = registry;
    }

    /// <summary>
    /// Start orchestrator - maintains minimum ready servers
    /// </summary>
    public async Task StartAsync(CancellationToken ct)
    {
        Console.WriteLine("[Orchestrator] Starting...");

        // Spawn initial servers
        await EnsureMinimumServersAsync();

        // Monitor loop
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), ct);

                // Check for timed out servers
                CheckHeartbeats();

                // Check for crashed processes
                CheckProcessHealth();

                // Ensure minimum servers
                await EnsureMinimumServersAsync();
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Orchestrator] Error: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Spawn a new game server
    /// </summary>
    public async Task<GameServer?> SpawnServerAsync()
    {
        var port = AllocatePort();
        if (port == -1)
        {
            Console.WriteLine("[Orchestrator] No available ports");
            return null;
        }

        try
        {
            var process = StartGodotServer(port);
            if (process == null)
            {
                ReleasePort(port);
                return null;
            }

            var server = _registry.RegisterServer(port, process.Id);

            lock (_lock)
            {
                _processes[server.Id] = process;
            }

            Console.WriteLine($"[Orchestrator] Server spawned: {server.Id} (PID {process.Id}, port {port})");

            // Server will call /servers/ready when it's initialized
            return server;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Orchestrator] Failed to spawn server: {ex.Message}");
            ReleasePort(port);
            return null;
        }
    }

    /// <summary>
    /// Terminate a server
    /// </summary>
    public void TerminateServer(string serverId, string reason = "")
    {
        Process? process = null;

        lock (_lock)
        {
            _processes.TryGetValue(serverId, out process);
            _processes.Remove(serverId);
        }

        var server = _registry.GetServer(serverId);
        if (server != null)
        {
            ReleasePort(server.Port);
            _registry.UnregisterServer(serverId);
        }

        if (process != null && !process.HasExited)
        {
            try
            {
                // Try graceful shutdown first
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Orchestrator] Error terminating process: {ex.Message}");
            }
        }

        Console.WriteLine($"[Orchestrator] Server terminated: {serverId} ({reason})");
    }

    /// <summary>
    /// Shutdown all servers
    /// </summary>
    public void ShutdownAll()
    {
        Console.WriteLine("[Orchestrator] Shutting down all servers...");

        List<string> serverIds;
        lock (_lock)
        {
            serverIds = _processes.Keys.ToList();
        }

        foreach (var id in serverIds)
        {
            TerminateServer(id, "shutdown");
        }
    }

    /// <summary>
    /// Get an available server for a new match
    /// </summary>
    public GameServer? GetAvailableServer()
    {
        return _registry.GetAvailableServers().FirstOrDefault();
    }

    // ============================================
    // PRIVATE HELPERS
    // ============================================

    private async Task EnsureMinimumServersAsync()
    {
        var readyCount = _registry.GetAllServers().Count(s =>
            s.Status == ServerStatus.Ready || s.Status == ServerStatus.Starting);

        var needed = _config.MinReadyServers - readyCount;

        for (int i = 0; i < needed; i++)
        {
            await SpawnServerAsync();
        }
    }

    private void CheckHeartbeats()
    {
        var timeout = TimeSpan.FromSeconds(_config.HeartbeatTimeoutSeconds);
        var timedOut = _registry.GetTimedOutServers(timeout);

        foreach (var serverId in timedOut)
        {
            Console.WriteLine($"[Orchestrator] Server timed out: {serverId}");
            TerminateServer(serverId, "heartbeat_timeout");
        }
    }

    private void CheckProcessHealth()
    {
        List<(string id, Process proc)> toCheck;

        lock (_lock)
        {
            toCheck = _processes.Select(kvp => (kvp.Key, kvp.Value)).ToList();
        }

        foreach (var (serverId, process) in toCheck)
        {
            if (process.HasExited)
            {
                Console.WriteLine($"[Orchestrator] Process exited: {serverId} (exit code {process.ExitCode})");
                TerminateServer(serverId, $"process_exit_{process.ExitCode}");
            }
        }
    }

    private Process? StartGodotServer(int port)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = _config.GodotServerPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        // Godot CLI arguments
        startInfo.ArgumentList.Add("--headless");

        if (!string.IsNullOrEmpty(_config.GodotProjectPath))
        {
            startInfo.ArgumentList.Add("--path");
            startInfo.ArgumentList.Add(_config.GodotProjectPath);
        }

        // Pass port via environment
        startInfo.Environment["GAME_PORT"] = port.ToString();
        startInfo.Environment["BACKEND_HOST"] = "127.0.0.1";
        startInfo.Environment["BACKEND_PORT"] = _config.HttpPort.ToString();

        try
        {
            var process = Process.Start(startInfo);
            if (process == null)
            {
                Console.WriteLine("[Orchestrator] Failed to start process");
                return null;
            }

            // Log output (optional, for debugging)
            process.OutputDataReceived += (_, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                    Console.WriteLine($"[Server:{port}] {e.Data}");
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                    Console.WriteLine($"[Server:{port}] ERR: {e.Data}");
            };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            return process;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Orchestrator] Process start error: {ex.Message}");
            return null;
        }
    }

    private int AllocatePort()
    {
        lock (_lock)
        {
            for (int i = 0; i < _config.MaxServers; i++)
            {
                var port = _config.BaseGamePort + i;
                if (!_usedPorts.Contains(port))
                {
                    _usedPorts.Add(port);
                    return port;
                }
            }
        }
        return -1;
    }

    private void ReleasePort(int port)
    {
        lock (_lock)
        {
            _usedPorts.Remove(port);
        }
    }
}
