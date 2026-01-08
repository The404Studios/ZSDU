using System;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace TraversalServer;

/// <summary>
/// Main traversal server handling TCP connections from game clients
/// </summary>
public class Server
{
    private readonly int _port;
    private readonly TcpListener _listener;
    private readonly ConcurrentDictionary<string, Session> _sessions = new();
    private readonly ConcurrentDictionary<EndPoint, ClientConnection> _clients = new();

    // Settings
    private readonly TimeSpan _heartbeatTimeout = TimeSpan.FromSeconds(30);
    private readonly TimeSpan _cleanupInterval = TimeSpan.FromSeconds(10);

    public Server(int port)
    {
        _port = port;
        _listener = new TcpListener(IPAddress.Any, port);
    }

    public async Task RunAsync(CancellationToken ct)
    {
        _listener.Start();
        Console.WriteLine($"[Server] Listening on port {_port}");

        // Start cleanup task
        _ = CleanupLoopAsync(ct);

        // Accept connections
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
                Console.WriteLine($"[Server] Accept error: {ex.Message}");
            }
        }

        _listener.Stop();
    }

    private async Task HandleClientAsync(TcpClient tcpClient, CancellationToken ct)
    {
        var endpoint = tcpClient.Client.RemoteEndPoint!;
        var clientIp = ((IPEndPoint)endpoint).Address.ToString();

        Console.WriteLine($"[Server] Client connected: {clientIp}");

        var connection = new ClientConnection(tcpClient, clientIp);
        _clients[endpoint] = connection;

        try
        {
            var stream = tcpClient.GetStream();
            var buffer = new byte[4096];
            var receiveBuffer = new byte[0];

            while (!ct.IsCancellationRequested && tcpClient.Connected)
            {
                // Read data
                var bytesRead = await stream.ReadAsync(buffer, ct);
                if (bytesRead == 0)
                    break;

                // Append to receive buffer
                var newBuffer = new byte[receiveBuffer.Length + bytesRead];
                receiveBuffer.CopyTo(newBuffer, 0);
                buffer.AsSpan(0, bytesRead).CopyTo(newBuffer.AsSpan(receiveBuffer.Length));
                receiveBuffer = newBuffer;

                // Process complete messages
                while (true)
                {
                    var consumed = Protocol.TryDecodeMessage(
                        receiveBuffer,
                        out var msgType,
                        out var payload);

                    if (consumed == 0)
                        break;

                    // Remove processed bytes
                    receiveBuffer = receiveBuffer.AsSpan(consumed).ToArray();

                    // Handle message
                    await HandleMessageAsync(connection, msgType, payload, stream);
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Server] Client error ({clientIp}): {ex.Message}");
        }
        finally
        {
            // Cleanup
            _clients.TryRemove(endpoint, out _);

            // Remove any sessions owned by this client
            if (connection.OwnedSessionId != null)
            {
                if (_sessions.TryRemove(connection.OwnedSessionId, out var session))
                {
                    Console.WriteLine($"[Server] Session removed (client disconnect): {session.Name}");
                }
            }

            tcpClient.Close();
            Console.WriteLine($"[Server] Client disconnected: {clientIp}");
        }
    }

    private async Task HandleMessageAsync(
        ClientConnection client,
        MessageType type,
        string payload,
        NetworkStream stream)
    {
        try
        {
            switch (type)
            {
                case MessageType.RegisterHost:
                    await HandleRegisterHostAsync(client, payload, stream);
                    break;

                case MessageType.UnregisterHost:
                    HandleUnregisterHost(client, payload);
                    break;

                case MessageType.ListSessions:
                    await HandleListSessionsAsync(stream);
                    break;

                case MessageType.JoinSession:
                    await HandleJoinSessionAsync(payload, stream);
                    break;

                case MessageType.Heartbeat:
                    await HandleHeartbeatAsync(payload, stream);
                    break;

                default:
                    Console.WriteLine($"[Server] Unknown message type: {type}");
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Server] Error handling {type}: {ex.Message}");
            await SendErrorAsync(stream, ex.Message);
        }
    }

    private async Task HandleRegisterHostAsync(
        ClientConnection client,
        string payload,
        NetworkStream stream)
    {
        var request = JsonSerializer.Deserialize<RegisterHostRequest>(
            payload,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (request == null)
        {
            await SendErrorAsync(stream, "Invalid registration data");
            return;
        }

        var session = new Session
        {
            Name = request.Name,
            HostIp = client.IpAddress,
            HostPort = request.Port,
            MaxPlayers = request.MaxPlayers,
            CurrentPlayers = request.CurrentPlayers,
            GameVersion = request.GameVersion,
            HostEndpoint = client.TcpClient.Client.RemoteEndPoint
        };

        _sessions[session.Id] = session;
        client.OwnedSessionId = session.Id;

        Console.WriteLine($"[Server] Session registered: {session.Name} ({session.Id}) - {client.IpAddress}:{request.Port}");

        // Send session ID back
        var response = Protocol.EncodeMessage(MessageType.SessionCreated, session.Id);
        await stream.WriteAsync(response);
    }

    private void HandleUnregisterHost(ClientConnection client, string sessionId)
    {
        if (_sessions.TryRemove(sessionId, out var session))
        {
            Console.WriteLine($"[Server] Session unregistered: {session.Name}");
            client.OwnedSessionId = null;
        }
    }

    private async Task HandleListSessionsAsync(NetworkStream stream)
    {
        var sessionList = _sessions.Values
            .Where(s => !s.IsTimedOut(_heartbeatTimeout))
            .Select(s => s.ToPublicInfo())
            .ToArray();

        Console.WriteLine($"[Server] Sending session list ({sessionList.Length} sessions)");

        var json = JsonSerializer.Serialize(sessionList, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
        });

        var response = Protocol.EncodeMessage(MessageType.SessionList, json);
        await stream.WriteAsync(response);
    }

    private async Task HandleJoinSessionAsync(string sessionId, NetworkStream stream)
    {
        if (!_sessions.TryGetValue(sessionId.Trim(), out var session))
        {
            await SendErrorAsync(stream, "Session not found");
            return;
        }

        if (session.IsTimedOut(_heartbeatTimeout))
        {
            _sessions.TryRemove(sessionId, out _);
            await SendErrorAsync(stream, "Session timed out");
            return;
        }

        Console.WriteLine($"[Server] Client joining session: {session.Name}");

        var joinInfo = new JoinInfo
        {
            HostIp = session.HostIp,
            HostPort = session.HostPort
        };

        var response = Protocol.EncodeMessage(MessageType.JoinInfo, joinInfo);
        await stream.WriteAsync(response);
    }

    private async Task HandleHeartbeatAsync(string payload, NetworkStream stream)
    {
        var request = JsonSerializer.Deserialize<HeartbeatRequest>(
            payload,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (request == null)
            return;

        if (_sessions.TryGetValue(request.SessionId, out var session))
        {
            session.RefreshHeartbeat();
            session.CurrentPlayers = request.CurrentPlayers;
        }

        // Send ack
        var response = Protocol.EncodeMessage(MessageType.HeartbeatAck, "");
        await stream.WriteAsync(response);
    }

    private async Task SendErrorAsync(NetworkStream stream, string message)
    {
        var response = Protocol.EncodeMessage(MessageType.Error, message);
        await stream.WriteAsync(response);
    }

    private async Task CleanupLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(_cleanupInterval, ct);

                // Remove timed out sessions
                var timedOut = _sessions
                    .Where(kvp => kvp.Value.IsTimedOut(_heartbeatTimeout))
                    .Select(kvp => kvp.Key)
                    .ToList();

                foreach (var id in timedOut)
                {
                    if (_sessions.TryRemove(id, out var session))
                    {
                        Console.WriteLine($"[Server] Session timed out: {session.Name}");
                    }
                }

                // Log status periodically
                Console.WriteLine($"[Server] Active sessions: {_sessions.Count}, Connected clients: {_clients.Count}");
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Server] Cleanup error: {ex.Message}");
            }
        }
    }
}

/// <summary>
/// Represents a connected client
/// </summary>
public class ClientConnection
{
    public TcpClient TcpClient { get; }
    public string IpAddress { get; }
    public string? OwnedSessionId { get; set; }
    public DateTime ConnectedAt { get; } = DateTime.UtcNow;

    public ClientConnection(TcpClient client, string ipAddress)
    {
        TcpClient = client;
        IpAddress = ipAddress;
    }
}
