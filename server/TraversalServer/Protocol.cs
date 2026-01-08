using System;
using System.Text;
using System.Text.Json;

namespace TraversalServer;

/// <summary>
/// Protocol message types matching the Godot client
/// </summary>
public enum MessageType : byte
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

/// <summary>
/// Protocol utilities for message encoding/decoding
/// </summary>
public static class Protocol
{
    /// <summary>
    /// Encode a message with length prefix: [4 bytes length][1 byte type][payload]
    /// </summary>
    public static byte[] EncodeMessage(MessageType type, string payload)
    {
        var payloadBytes = Encoding.UTF8.GetBytes(payload);
        var messageLength = 1 + payloadBytes.Length; // type + payload

        var packet = new byte[4 + messageLength];

        // Length prefix (little-endian)
        BitConverter.GetBytes((uint)messageLength).CopyTo(packet, 0);

        // Message type
        packet[4] = (byte)type;

        // Payload
        payloadBytes.CopyTo(packet, 5);

        return packet;
    }

    /// <summary>
    /// Encode a message with a JSON object payload
    /// </summary>
    public static byte[] EncodeMessage<T>(MessageType type, T payload)
    {
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
        });
        return EncodeMessage(type, json);
    }

    /// <summary>
    /// Try to decode a message from buffer
    /// </summary>
    /// <returns>Number of bytes consumed, or 0 if incomplete message</returns>
    public static int TryDecodeMessage(
        ReadOnlySpan<byte> buffer,
        out MessageType type,
        out string payload)
    {
        type = 0;
        payload = "";

        // Need at least 4 bytes for length
        if (buffer.Length < 4)
            return 0;

        // Read length (little-endian)
        var length = BitConverter.ToUInt32(buffer.Slice(0, 4));

        // Check if we have the full message
        if (buffer.Length < 4 + length)
            return 0;

        // Read message type
        type = (MessageType)buffer[4];

        // Read payload
        if (length > 1)
        {
            payload = Encoding.UTF8.GetString(buffer.Slice(5, (int)length - 1));
        }

        return 4 + (int)length;
    }
}

/// <summary>
/// Registration request from a host
/// </summary>
public class RegisterHostRequest
{
    public string Name { get; set; } = "";
    public int Port { get; set; }
    public int MaxPlayers { get; set; }
    public int CurrentPlayers { get; set; }
    public string GameVersion { get; set; } = "";
}

/// <summary>
/// Heartbeat from a host
/// </summary>
public class HeartbeatRequest
{
    public string SessionId { get; set; } = "";
    public int CurrentPlayers { get; set; }
}

/// <summary>
/// Join info sent to a client
/// </summary>
public class JoinInfo
{
    public string HostIp { get; set; } = "";
    public int HostPort { get; set; }
}
