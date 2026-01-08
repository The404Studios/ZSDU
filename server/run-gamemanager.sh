#!/bin/bash
# ZSDU Game Manager startup script

cd "$(dirname "$0")/GameManager"

# Build if needed
if [ ! -f "bin/Release/net8.0/GameManager" ]; then
    echo "Building Game Manager..."
    dotnet build -c Release
fi

# Run the Game Manager
echo "Starting ZSDU Game Manager..."
echo "HTTP Port: ${HTTP_PORT:-8080}"
echo "WebSocket Port: ${WS_PORT:-8081}"
echo ""
dotnet run -c Release
