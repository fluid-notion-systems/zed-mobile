# Using Zed's Local Collaboration Server for Mobile Development

This guide explains how to use Zed's existing collaboration server locally for developing and testing Zed Mobile features, particularly agent integration.

## Overview

Zed already includes a full-featured collaboration server that can be run locally. This server provides:
- WebSocket-based RPC communication
- Authentication and user management
- Project sharing and collaboration
- Real-time event streaming
- LiveKit integration for audio/video (optional)

For mobile development, we can leverage this existing infrastructure instead of building custom solutions.

## Prerequisites

### Option 1: PostgreSQL with Docker (Recommended)

1. **Install Docker**
   ```bash
   # Ubuntu/Debian
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   
   # Add your user to docker group (requires logout/login)
   sudo usermod -aG docker $USER
   ```

2. **Start PostgreSQL in Docker**
   ```bash
   # From the zed-mobile directory
   ./scripts/docker-postgres.sh start
   ```
   
   This will:
   - Create a PostgreSQL container named `zed-postgres`
   - Set up databases: `zed` and `zed_llm`
   - Save connection info to `tmp/postgres-docker/connection-info.env`

### Option 2: SQLite (Simpler, but Limited)

No additional setup required! SQLite will be used automatically if PostgreSQL is not available.

**Note**: SQLite mode currently has issues with the LLM database requirements. PostgreSQL is recommended.

### Option 3: Native PostgreSQL

Follow the [local collaboration setup](../vendor/zed/docs/src/development/local-collaboration.md) guide to install PostgreSQL natively.

## Running the Local Server

### Quick Start: Using the Script (Recommended)

```bash
# From the zed-mobile directory

# For PostgreSQL (with Docker)
./scripts/docker-postgres.sh start  # Start PostgreSQL first
./scripts/zed-local-collab.sh --postgres

# For SQLite (limited functionality)
./scripts/zed-local-collab.sh
```

This script automatically:
- Checks dependencies (PostgreSQL/SQLite)
- Sets up the database if needed
- Starts the collab server
- Launches Zed with the correct configuration
- Shows connection information for mobile devices

### Manual Setup Options

#### Option 1: With Foreman
```bash
cd vendor/zed
foreman start
```

This starts both the collab server and LiveKit dev server.

#### Option 2: Collab Server Only
```bash
cd vendor/zed
cargo run -p collab -- serve all
```

#### Option 3: With SQLite (No PostgreSQL Required)
```bash
cd vendor/zed
cargo run -p collab --features sqlite -- serve all
```

## Docker PostgreSQL Management

The `docker-postgres.sh` script provides several commands:

```bash
# Start PostgreSQL
./scripts/docker-postgres.sh start

# Stop PostgreSQL
./scripts/docker-postgres.sh stop

# Restart PostgreSQL
./scripts/docker-postgres.sh restart

# Check status
./scripts/docker-postgres.sh status

# View logs
./scripts/docker-postgres.sh logs

# Remove container and data
./scripts/docker-postgres.sh remove
```

Connection details when using Docker:
- Host: `localhost`
- Port: `5432`
- User: `postgres`
- Password: `postgres`
- Database: `zed`
- Connection URL: `postgres://postgres:postgres@localhost:5432/zed`

## Configuring Zed Desktop to Use Local Server

### Automatic Configuration (Using Script)
The `zed-local-collab.sh` script handles all configuration automatically.

### Manual Configuration
Set the following environment variables when running Zed:

```bash
# Set the server URL to localhost
export ZED_SERVER_URL="http://localhost:8080"

# Set the API token (must match .env.toml)
export ZED_ADMIN_API_TOKEN="secret"

# Impersonate a user from seed.json
export ZED_IMPERSONATE="nathansobo"

# Run Zed
cd vendor/zed
cargo run
```

## Connecting from Mobile

The mobile app can connect to the local collab server using the same RPC protocol:

1. **Configure the server URL** in the mobile app to point to your local machine:
   - For Android emulator: `http://10.0.2.2:8080`
   - For iOS simulator: `http://localhost:8080`
   - For physical device: `http://<your-ip>:8080`

2. **Authentication**: Use the same API token and impersonation approach

## Agent Event Integration

While the current collab server doesn't yet stream agent events, the infrastructure is in place:

1. The agent system already has an EventBridge that converts GPUI events to core events
2. The collab server has a robust RPC protocol for streaming data
3. Adding agent event streaming would involve:
   - Extending the RPC protocol with agent event types
   - Subscribing to the agent event bus in the collab server
   - Streaming events to connected clients

## Troubleshooting

### Docker Permission Issues
If you get "permission denied" errors with Docker:
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply changes (or logout/login)
newgrp docker
```

### PostgreSQL Connection Issues
Check if PostgreSQL is running:
```bash
./scripts/docker-postgres.sh status
```

View PostgreSQL logs:
```bash
./scripts/docker-postgres.sh logs
```

### SQLite Mode Issues
SQLite mode currently doesn't support the LLM database, which causes issues with:
- Database seeding
- Running in "all" mode

Use PostgreSQL for full functionality.

### Server Won't Start
1. Check if port 8080 is already in use:
   ```bash
   lsof -i :8080
   ```

2. Kill any existing collab processes:
   ```bash
   pkill -f "collab serve"
   ```

3. Check the logs for errors:
   ```bash
   RUST_LOG=debug ./scripts/zed-local-collab.sh
   ```

## Current Limitations

1. **Agent Events**: Not yet exposed through RPC (requires protocol extension)
2. **Discovery**: No automatic local server discovery (must configure URL manually)
3. **Authentication**: Simplified auth suitable only for development
4. **SQLite Mode**: Limited functionality due to LLM database requirements

## Future Enhancements

1. **Agent Event Streaming**: Add agent-specific message types to the RPC protocol
2. **mDNS Discovery**: Automatic discovery of local Zed instances
3. **Simplified Auth**: Pairing codes for easier mobile connection
4. **SQLite Compatibility**: Fix LLM database issues for simpler local development

## Development Workflow

1. Start Docker PostgreSQL (if using PostgreSQL)
2. Run the local collab script
3. Connect mobile app to the server
4. Both clients can now communicate through the shared server

## Debugging

Enable debug logging:
```bash
RUST_LOG=collab=debug,rpc=debug ./scripts/zed-local-collab.sh
```

View server logs to see:
- Client connections
- RPC messages
- Authentication attempts
- Error messages

## Next Steps

1. Experiment with the existing RPC protocol to understand message flow
2. Identify which agent events need to be exposed
3. Propose RPC protocol extensions for agent functionality
4. Implement agent event streaming in the collab server

This approach leverages existing, battle-tested infrastructure rather than building new systems from scratch.