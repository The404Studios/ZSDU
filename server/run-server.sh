#!/bin/bash
# ZSDU Traversal Server startup script

cd "$(dirname "$0")/TraversalServer"

# Build if needed
if [ ! -f "bin/Release/net8.0/TraversalServer" ]; then
    echo "Building server..."
    dotnet build -c Release
fi

# Run the server
PORT=${1:-7777}
echo "Starting ZSDU Traversal Server on port $PORT..."
dotnet run -c Release -- $PORT
