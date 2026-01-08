namespace GameManager;

/// <summary>
/// Server configuration - can be loaded from environment or config file
/// </summary>
public class Configuration
{
    // HTTP API
    public int HttpPort { get; set; } = 8080;
    public string HttpHost { get; set; } = "0.0.0.0";

    // WebSocket
    public int WebSocketPort { get; set; } = 8081;

    // Traversal/Session Discovery (legacy support)
    public int TraversalPort { get; set; } = 7777;

    // Game Server Management
    public int MinGameServers { get; set; } = 1;
    public int MaxGameServers { get; set; } = 100;
    public int PlayersPerServer { get; set; } = 32;
    public int GameServerBasePort { get; set; } = 27015;

    // Timeouts
    public int SessionTimeoutSeconds { get; set; } = 60;
    public int HeartbeatIntervalSeconds { get; set; } = 15;
    public int MatchmakingTimeoutSeconds { get; set; } = 120;

    // Cache (Redis-like)
    public string CacheHost { get; set; } = "localhost";
    public int CachePort { get; set; } = 6379;
    public bool UseCacheCluster { get; set; } = false;

    // Database
    public string DatabaseHost { get; set; } = "localhost";
    public int DatabasePort { get; set; } = 3306;
    public string DatabaseName { get; set; } = "zsdu";
    public string DatabaseUser { get; set; } = "root";
    public string DatabasePassword { get; set; } = "";

    // Kubernetes
    public bool RunInKubernetes { get; set; } = false;
    public string K8sNamespace { get; set; } = "zsdu";
    public string GameServerImage { get; set; } = "zsdu/gameserver:latest";

    /// <summary>
    /// Load configuration from environment variables
    /// </summary>
    public static Configuration FromEnvironment()
    {
        var config = new Configuration();

        // HTTP
        if (int.TryParse(Environment.GetEnvironmentVariable("HTTP_PORT"), out var httpPort))
            config.HttpPort = httpPort;
        if (int.TryParse(Environment.GetEnvironmentVariable("WS_PORT"), out var wsPort))
            config.WebSocketPort = wsPort;

        // Game servers
        if (int.TryParse(Environment.GetEnvironmentVariable("MIN_SERVERS"), out var minServers))
            config.MinGameServers = minServers;
        if (int.TryParse(Environment.GetEnvironmentVariable("MAX_SERVERS"), out var maxServers))
            config.MaxGameServers = maxServers;
        if (int.TryParse(Environment.GetEnvironmentVariable("PLAYERS_PER_SERVER"), out var pps))
            config.PlayersPerServer = pps;

        // Cache
        config.CacheHost = Environment.GetEnvironmentVariable("REDIS_HOST") ?? config.CacheHost;
        if (int.TryParse(Environment.GetEnvironmentVariable("REDIS_PORT"), out var redisPort))
            config.CachePort = redisPort;

        // Database
        config.DatabaseHost = Environment.GetEnvironmentVariable("MYSQL_HOST") ?? config.DatabaseHost;
        config.DatabaseName = Environment.GetEnvironmentVariable("MYSQL_DATABASE") ?? config.DatabaseName;
        config.DatabaseUser = Environment.GetEnvironmentVariable("MYSQL_USER") ?? config.DatabaseUser;
        config.DatabasePassword = Environment.GetEnvironmentVariable("MYSQL_PASSWORD") ?? config.DatabasePassword;

        // Kubernetes
        config.RunInKubernetes = Environment.GetEnvironmentVariable("KUBERNETES_SERVICE_HOST") != null;
        config.K8sNamespace = Environment.GetEnvironmentVariable("K8S_NAMESPACE") ?? config.K8sNamespace;
        config.GameServerImage = Environment.GetEnvironmentVariable("GAMESERVER_IMAGE") ?? config.GameServerImage;

        return config;
    }
}
