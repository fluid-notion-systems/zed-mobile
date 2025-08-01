# Zed Collab Server Architecture

## Overview

The Zed collaboration server (collab) is a sophisticated real-time collaboration system that enables multiple Zed clients to work together on shared projects. It handles authentication, RPC message routing, persistent storage, and integration with external services like LiveKit for audio/video calls.

## Core Components

### 1. Server Structure (`crates/collab/src/main.rs`)

The main server application with multiple service modes:

```rust
pub enum ServiceMode {
    Api,      // REST API endpoints only
    Collab,   // WebSocket RPC server
    All,      // Both API and Collab
}
```

**Key Entry Points:**
- `main()` - CLI interface supporting `migrate`, `seed`, and `serve` commands
- `serve <api|collab|all>` - Starts the server in specified mode

### 2. RPC Server (`crates/collab/src/rpc.rs`)

The heart of real-time collaboration, handling WebSocket connections and message routing.

**Core Types:**
```rust
pub struct Server {
    id: parking_lot::Mutex<ServerId>,
    peer: Arc<Peer>,                              // From rpc crate - manages connections
    app_state: Arc<AppState>,                     // Shared application state
    connection_pool: Arc<ConnectionPool>,         // Active connections
    handlers: HashMap<TypeId, MessageHandler>,    // RPC message handlers
}

pub struct Session {
    principal: Principal,                         // Authenticated user/admin
    connection_id: ConnectionId,
    db: Arc<tokio::sync::Mutex<DbHandle>>,
    peer: Arc<Peer>,
    connection_pool: Arc<ConnectionPool>,
}
```

**Message Handler Registration Pattern:**
```rust
server
    .add_request_handler(handler_function)    // For request/response
    .add_message_handler(handler_function)    // For one-way messages
```

### 3. Connection Pool (`crates/collab/src/rpc/connection_pool.rs`)

Manages all active client connections and their state.

**Key Structures:**
```rust
pub struct ConnectionPool {
    connections: RwLock<HashMap<ConnectionId, ConnectionState>>,
    connected_users: RwLock<HashMap<UserId, ConnectedUser>>,
    channels: RwLock<HashMap<ChannelId, ChannelState>>,
}

struct ConnectionState {
    user_id: UserId,
    admin: bool,
    zed_version: ZedVersion,
    projects: HashSet<ProjectId>,
    subscriptions: HashSet<ChannelId>,
}
```

### 4. Database Layer (`crates/collab/src/db/`)

PostgreSQL-based persistence with comprehensive query modules.

**Core Database Structure:**
```rust
pub struct Database {
    options: ConnectOptions,
    pool: AnyPool,
    runtime: Option<tokio::runtime::Runtime>,
}
```

**Query Modules** (in `src/db/queries/`):
- `users.rs` - User management
- `projects.rs` - Project collaboration
- `rooms.rs` - Voice/video rooms
- `channels.rs` - Chat channels
- `buffers.rs` - Shared buffer state
- `messages.rs` - Channel messages
- `access_tokens.rs` - Authentication tokens

### 5. Authentication (`crates/collab/src/auth.rs`)

JWT-based authentication with multiple token types:

```rust
pub enum Principal {
    User(User),
    Impersonated { user: User, admin: User },
    Admin(User),
}

pub struct AccessTokenClaims {
    pub iat: u64,         // Issued at
    pub exp: u64,         // Expiration
    pub jti: String,      // JWT ID
    pub user_id: UserId,
    pub is_admin: bool,
    pub impersonated_user_id: Option<UserId>,
}
```

## Key Terminology

### Connection & Identity

- **ConnectionId**: Unique identifier for a WebSocket connection
- **UserId**: Persistent user identifier
- **Principal**: Authenticated entity (user or admin)
- **Session**: Active connection context with authentication

### Collaboration Concepts

- **Project**: Shared workspace with files and language servers
- **Room**: Voice/video call space with screen sharing
- **Channel**: Persistent chat room with members
- **Buffer**: Shared text buffer for collaborative editing
- **Worktree**: File tree within a project

### RPC Message Types

- **Request/Response**: Client sends request, expects response
- **Message**: One-way notification
- **Entity Messages**: Updates to shared entities (projects, buffers)
- **Envelope**: Wrapper for all RPC messages with metadata

## RPC Protocol

### Message Flow

1. **Client → Server**: TypedEnvelope containing request/message
2. **Server Processing**: Route to appropriate handler based on message type
3. **Server → Client**: Response or broadcast to relevant clients

### Key RPC Handlers

**Project Collaboration:**
- `share_project` - Make project available for collaboration
- `join_project` - Join another user's project
- `update_project` - Sync project metadata
- `update_buffer` - Collaborative editing operations

**Communication:**
- `join_room` - Join voice/video call
- `join_channel` - Join chat channel
- `send_channel_message` - Send chat message
- `update_participant_location` - Share cursor position

**AI/Assistant:**
- `get_llm_api_token` - Retrieve LLM API token
- `update_context` - AI context operations
- `open_context` - Open AI conversation

### Message Handler Example

```rust
async fn join_project(
    request: proto::JoinProject,
    response: Response<proto::JoinProject>,
    session: Session,
) -> Result<()> {
    let project_id = ProjectId::from_proto(request.project_id);
    let db = session.db().await;
    
    // Authorization check
    let project = db.get_project(project_id, session.user_id).await?;
    
    // Add to connection pool
    let pool = session.connection_pool().await;
    pool.join_project(session.connection_id, project_id);
    
    // Send response
    response.send(proto::JoinProjectResponse {
        worktrees: serialize_worktrees(&project.worktrees),
        collaborators: serialize_collaborators(&project.collaborators),
    })?;
    
    Ok(())
}
```

## Database Schema

### Core Tables

**users**
- id, email, github_user_id, admin, metrics_id
- created_at, invited_to_slack, connected_once

**projects**  
- id, host_user_id, host_connection_id
- room_id, created_at, dev_server_id

**rooms**
- id, live_kit_room, environment
- created_at, channel_id

**channels**
- id, name, visibility, parent_id
- created_at, updated_at

**channel_members**
- channel_id, user_id, role, permissions

**buffers**
- id, channel_id, created_at, epoch

### Relationship Model

```
User ──┬── hosts ──> Project
       ├── participates ──> Room
       └── member_of ──> Channel ──> contains ──> Buffer
```

## External Integrations

### LiveKit (Audio/Video)

```rust
pub struct LiveKitClient {
    api_key: String,
    api_secret: String,
    url: String,
}

// Creates room tokens for WebRTC connections
pub fn create_room_token(room: &str, user_id: &str) -> Result<String>
```

### Stripe (Billing)

```rust
pub struct StripeClient {
    api: stripe::Client,
    price_ids: HashMap<String, String>,
}

// Manages subscriptions and usage tracking
```

### GitHub (Authentication & Extensions)

- OAuth for user authentication
- App installation for repository access
- Webhook handling for events

## API Endpoints (`crates/collab/src/api/`)

### REST API Routes

**Authentication:**
- `POST /user` - Create/update user
- `GET /user` - Get current user
- `POST /signout` - Sign out

**Extensions:**
- `GET /extensions` - List extensions
- `POST /extensions` - Publish extension
- `GET /extensions/:id/download` - Download extension

**Billing:**
- `POST /billing/subscriptions` - Manage subscriptions
- `GET /billing/customers` - Customer info

## Event System

### Internal Events

The server maintains internal event streams for:
- Connection lifecycle (connect/disconnect)
- Project updates
- Channel activity
- Room state changes

### Event Broadcasting

```rust
impl Server {
    fn broadcast_to_room(&self, room_id: RoomId, message: impl Message) {
        let connections = self.connection_pool
            .connections_in_room(room_id);
            
        for connection_id in connections {
            self.peer.send(connection_id, message.clone());
        }
    }
}
```

## Performance & Scaling

### Connection Management

- **Concurrent connections**: Limited by `MAX_CONCURRENT_CONNECTIONS`
- **Message queuing**: Per-connection message buffers
- **Heartbeat/ping**: Keep-alive mechanism for connections

### Database Optimization

- **Connection pooling**: Via sqlx
- **Query optimization**: Prepared statements
- **Caching**: In-memory caches for hot data

### Resource Cleanup

```rust
// Periodic cleanup of stale resources
async fn cleanup_stale_resources(server_id: ServerId) {
    // Remove disconnected participants
    db.clear_stale_room_participants(room_id, server_id).await;
    
    // Clean up abandoned projects
    db.delete_stale_projects(server_id).await;
    
    // Clear old channel participants
    db.delete_stale_channel_chat_participants(server_id).await;
}
```

## Security

### Authentication Flow

1. Client presents JWT token in WebSocket upgrade
2. Server validates token and extracts claims
3. Session created with appropriate Principal
4. All subsequent operations check authorization

### Authorization Model

```rust
impl Database {
    async fn check_user_can_access_project(
        &self,
        user_id: UserId,
        project_id: ProjectId,
    ) -> Result<bool> {
        // Check if user is host or collaborator
        // Check if project is in a channel user has access to
        // Apply role-based permissions
    }
}
```

## Deployment Architecture

### Environment Configuration

```rust
pub struct Config {
    pub database_url: String,
    pub http_port: u16,
    pub live_kit_server: Option<String>,
    pub stripe_api_key: Option<String>,
    pub log_json: bool,
    pub zed_environment: String,  // "development", "staging", "production"
}
```

### Service Dependencies

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Clients   │────▶│ Collab Server│────▶│  PostgreSQL │
└─────────────┘     └──────┬───────┘     └─────────────┘
                           │
                    ┌──────┼──────┐
                    ▼      ▼      ▼
              ┌────────┐ ┌────┐ ┌────────┐
              │LiveKit │ │S3  │ │ Stripe │
              └────────┘ └────┘ └────────┘
```

## Mobile Integration Points

For integrating agent events into the collab server:

1. **Add to Protocol** (`proto/ai.proto`):
   - Define AgentEvent messages
   - Add subscription RPCs

2. **Create Handlers** (`src/rpc.rs`):
   - `subscribe_to_agent_events`
   - `unsubscribe_from_agent_events`
   - `broadcast_agent_event`

3. **Extend Session** (`src/rpc.rs`):
   - Track agent subscriptions per connection
   - Handle cleanup on disconnect

4. **Database Schema** (optional):
   - Store agent thread metadata
   - Track usage statistics

This architecture provides a robust foundation for real-time collaboration while maintaining security, scalability, and extensibility for features like agent event streaming.