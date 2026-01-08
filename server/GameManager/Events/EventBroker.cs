using System.Collections.Concurrent;
using System.Threading.Channels;

namespace GameManager.Events;

/// <summary>
/// In-memory event broker for service communication
/// In production, this would be replaced with KubeMQ/Redis/RabbitMQ
/// </summary>
public class EventBroker
{
    private readonly ConcurrentDictionary<string, List<Func<GameEvent, Task>>> _handlers = new();
    private readonly Channel<GameEvent> _eventQueue;
    private readonly CancellationTokenSource _cts = new();
    private Task? _processingTask;

    public EventBroker()
    {
        _eventQueue = Channel.CreateUnbounded<GameEvent>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = false
        });
    }

    /// <summary>
    /// Start processing events
    /// </summary>
    public void Start()
    {
        _processingTask = ProcessEventsAsync(_cts.Token);
    }

    /// <summary>
    /// Stop processing events
    /// </summary>
    public async Task StopAsync()
    {
        _cts.Cancel();
        _eventQueue.Writer.Complete();

        if (_processingTask != null)
        {
            await _processingTask;
        }
    }

    /// <summary>
    /// Publish an event to all subscribers
    /// </summary>
    public async Task PublishAsync(GameEvent evt)
    {
        await _eventQueue.Writer.WriteAsync(evt);
    }

    /// <summary>
    /// Publish synchronously (fire and forget)
    /// </summary>
    public void Publish(GameEvent evt)
    {
        _eventQueue.Writer.TryWrite(evt);
    }

    /// <summary>
    /// Subscribe to events of a specific type
    /// </summary>
    public void Subscribe<T>(Func<T, Task> handler) where T : GameEvent
    {
        var typeName = typeof(T).Name;

        _handlers.AddOrUpdate(
            typeName,
            _ => new List<Func<GameEvent, Task>> { e => handler((T)e) },
            (_, list) =>
            {
                list.Add(e => handler((T)e));
                return list;
            });
    }

    /// <summary>
    /// Subscribe to all events
    /// </summary>
    public void SubscribeAll(Func<GameEvent, Task> handler)
    {
        _handlers.AddOrUpdate(
            "*",
            _ => new List<Func<GameEvent, Task>> { handler },
            (_, list) =>
            {
                list.Add(handler);
                return list;
            });
    }

    private async Task ProcessEventsAsync(CancellationToken ct)
    {
        await foreach (var evt in _eventQueue.Reader.ReadAllAsync(ct))
        {
            try
            {
                var typeName = evt.GetType().Name;

                // Call type-specific handlers
                if (_handlers.TryGetValue(typeName, out var handlers))
                {
                    foreach (var handler in handlers)
                    {
                        try
                        {
                            await handler(evt);
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[EventBroker] Handler error for {typeName}: {ex.Message}");
                        }
                    }
                }

                // Call wildcard handlers
                if (_handlers.TryGetValue("*", out var allHandlers))
                {
                    foreach (var handler in allHandlers)
                    {
                        try
                        {
                            await handler(evt);
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[EventBroker] Wildcard handler error: {ex.Message}");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EventBroker] Processing error: {ex.Message}");
            }
        }
    }
}

/// <summary>
/// Event logging middleware - logs all events
/// </summary>
public class EventLogger
{
    public Task HandleEvent(GameEvent evt)
    {
        Console.WriteLine($"[Event] {evt.EventType} ({evt.EventId}) at {evt.Timestamp:HH:mm:ss.fff}");
        return Task.CompletedTask;
    }
}
