using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace ZSDU.Backend;

/// <summary>
/// TCP Traversal Server
/// Compatible with existing Godot TraversalClient
/// Handles session listing and join requests
/// </summary>
public class TraversalServer
{
    private readonly TcpListener _listener;
    private readonly Config _config;
    private readonly SessionRegistry _registry;

    // Protocol message types (matching Godot client)
    private enum MessageType : byte
    {
        // Client -> Server
        RegisterHost = 1,
        UnregisterHost = 2,
        ListSessions = 3,
        JoinSession = 4,
        Heartbeat = 5,

        // Server -> Client
        SessionCreated = 101,
        SessionList = 102,
        JoinInfo = 103,
        Error = 104,
        HeartbeatAck = 105,
    }

    public TraversalServer(Config config, SessionRegistry registry)
    {
        _config = config;
        _registry = registry;
        _listener = new TcpListener(IPAddress.Any, config.TraversalPort);
    }

    public async Task StartAsync(CancellationToken ct)
    {
        _listener.Start();
        Console.WriteLine($"[Traversal] Listening on port {_config.TraversalPort}");

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(ct);
                _ = HandleClientAsync(client, ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Traversal] Accept error: {ex.Message}");
            }
        }

        _listener.Stop();
    }

    private async Task HandleClientAsync(TcpClient tcpClient, CancellationToken ct)
    {
        var endpoint = tcpClient.Client.RemoteEndPoint?.ToString() ?? "unknown";
        Console.WriteLine($"[Traversal] Client connected: {endpoint}");

        try
        {
            var stream = tcpClient.GetStream();
            var buffer = new byte[4096];
            var receiveBuffer = Array.Empty<byte>();

            while (!ct.IsCancellationRequested && tcpClient.Connected)
            {
                var bytesRead = await stream.ReadAsync(buffer, ct);
                if (bytesRead == 0) break;

                // Append to buffer
                var newBuffer = new byte[receiveBuffer.Length + bytesRead];
                receiveBuffer.CopyTo(newBuffer, 0);
                Buffer.BlockCopy(buffer, 0, newBuffer, receiveBuffer.Length, bytesRead);
                receiveBuffer = newBuffer;

                // Process complete messages
                while (receiveBuffer.Length >= 4)
                {
                    var length = BitConverter.ToUInt32(receiveBuffer, 0);
                    if (receiveBuffer.Length < 4 + length) break;

                    var msgType = (MessageType)receiveBuffer[4];
                    var payload = receiveBuffer.Length > 5
                        ? Encoding.UTF8.GetString(receiveBuffer, 5, (int)length - 1)
                        : "";

                    // Remove processed bytes
                    receiveBuffer = receiveBuffer.Skip(4 + (int)length).ToArray();

                    // Handle message
                    await HandleMessageAsync(stream, endpoint, msgType, payload);
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Traversal] Client error ({endpoint}): {ex.Message}");
        }
        finally
        {
            tcpClient.Close();
            Console.WriteLine($"[Traversal] Client disconnected: {endpoint}");
        }
    }

    private async Task HandleMessageAsync(NetworkStream stream, string endpoint, MessageType type, string payload)
    {
        Console.WriteLine($"[Traversal] {endpoint}: {type}");

        switch (type)
        {
            case MessageType.ListSessions:
                await HandleListSessions(stream);
                break;

            case MessageType.JoinSession:
                await HandleJoinSession(stream, payload);
                break;

            case MessageType.RegisterHost:
                await HandleRegisterHost(stream, endpoint, payload);
                break;

            case MessageType.Heartbeat:
                await HandleHeartbeat(stream, payload);
                break;

            default:
                await SendMessage(stream, MessageType.Error, "Unknown message type");
                break;
        }
    }

    private async Task HandleListSessions(NetworkStream stream)
    {
        // Return all ready servers as "sessions"
        var sessions = _registry.GetAllServers()
            .Where(s => s.Status == ServerStatus.Ready || s.Status == ServerStatus.InGame)
            .Select(s => new
            {
                id = s.Id,
                name = $"Server {s.Id}",
                host_ip = GetPublicIp(),
                host_port = s.Port,
                max_players = s.MaxPlayers,
                current_players = s.CurrentPlayers,
                game_version = "1.0"
            })
            .ToArray();

        var json = JsonSerializer.Serialize(sessions);
        await SendMessage(stream, MessageType.SessionList, json);
    }

    private async Task HandleJoinSession(NetworkStream stream, string sessionId)
    {
        var server = _registry.GetServer(sessionId.Trim());
        if (server == null)
        {
            await SendMessage(stream, MessageType.Error, "Session not found");
            return;
        }

        var joinInfo = new
        {
            host_ip = GetPublicIp(),
            host_port = server.Port
        };

        var json = JsonSerializer.Serialize(joinInfo);
        await SendMessage(stream, MessageType.JoinInfo, json);
    }

    private async Task HandleRegisterHost(NetworkStream stream, string endpoint, string payload)
    {
        try
        {
            var request = JsonSerializer.Deserialize<HostRegistration>(payload, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (request == null)
            {
                await SendMessage(stream, MessageType.Error, "Invalid registration");
                return;
            }

            // Find or create server entry
            var server = _registry.GetServerByPort(request.Port);
            if (server == null)
            {
                server = _registry.RegisterServer(request.Port, 0);
            }
            _registry.ServerReady(server.Id);

            await SendMessage(stream, MessageType.SessionCreated, server.Id);
        }
        catch (Exception ex)
        {
            await SendMessage(stream, MessageType.Error, ex.Message);
        }
    }

    private async Task HandleHeartbeat(NetworkStream stream, string payload)
    {
        try
        {
            var request = JsonSerializer.Deserialize<HeartbeatData>(payload, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (request != null && !string.IsNullOrEmpty(request.SessionId))
            {
                _registry.ServerHeartbeat(request.SessionId, request.CurrentPlayers);
            }

            await SendMessage(stream, MessageType.HeartbeatAck, "");
        }
        catch
        {
            await SendMessage(stream, MessageType.HeartbeatAck, "");
        }
    }

    private async Task SendMessage(NetworkStream stream, MessageType type, string payload)
    {
        var payloadBytes = Encoding.UTF8.GetBytes(payload);
        var messageLength = 1 + payloadBytes.Length;

        var packet = new byte[4 + messageLength];
        BitConverter.GetBytes((uint)messageLength).CopyTo(packet, 0);
        packet[4] = (byte)type;
        payloadBytes.CopyTo(packet, 5);

        await stream.WriteAsync(packet);
    }

    private string GetPublicIp()
    {
        // For local development, return localhost
        // In production, this should return the actual public IP
        var publicIp = Environment.GetEnvironmentVariable("PUBLIC_IP");
        return !string.IsNullOrEmpty(publicIp) ? publicIp : "127.0.0.1";
    }

    private class HostRegistration
    {
        public string Name { get; set; } = "";
        public int Port { get; set; }
        public int MaxPlayers { get; set; }
        public int CurrentPlayers { get; set; }
        public string GameVersion { get; set; } = "";
    }

    private class HeartbeatData
    {
        public string SessionId { get; set; } = "";
        public int CurrentPlayers { get; set; }
    }
}
