# Zed Collaboration Architecture: In-Depth Analysis

## Table of Contents

1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Communication Protocol](#communication-protocol)
4. [Channel System Deep Dive](#channel-system-deep-dive)
5. [Real-Time Collaboration Mechanisms](#real-time-collaboration-mechanisms)
6. [Security and Authentication](#security-and-authentication)
7. [Performance Optimizations](#performance-optimizations)
8. [Mobile Integration Considerations](#mobile-integration-considerations)

## Overview

Zed's collaboration system is built on a sophisticated client-server architecture that enables real-time code collaboration, voice/video calls, and persistent chat channels. The system is designed for low latency, high reliability, and seamless integration with Zed's editor features.

### Key Design Principles

1. **Real-time First**: All collaboration features prioritize low-latency, real-time interaction
2. **Reliability**: Automatic reconnection, message persistence, and state synchronization
3. **Security**: End-to-end encryption options, role-based access control
4. **Scalability**: Designed to handle thousands of concurrent connections
5. **Extensibility**: Protocol designed for future features

## Architecture Components

### 1. Core Server (`collab/src/rpc.rs`)

The collaboration server is the central hub managing all real-time communication:

```rust
pub struct Server {
    id: parking_lot::Mutex<ServerId>,
    peer: Arc<Peer>,                          // WebSocket connection manager
    app_state: Arc<AppState>,                 // Shared application state
    connection_pool: Arc<ConnectionPool>,     // Active connection tracking
    handlers: HashMap<TypeId, MessageHandler>, // RPC message handlers
}
```

**Key Responsibilities:**
- WebSocket connection lifecycle management
- Message routing between clients
- State synchronization
- Authentication and authorization
- Integration with external services (LiveKit, PostgreSQL)

### 2. Connection Pool (`collab/src/rpc/connection_pool.rs`)

Manages active connections and their relationships:

```rust
pub struct ConnectionPool {
    connections: RwLock<HashMap<ConnectionId, Connection>>,
    connected_users: RwLock<HashMap<UserId, ConnectedPrincipal>>,
    channels: ChannelPool,
}

pub struct Connection {
    pub user_id: UserId,
    pub admin: bool,
    pub zed_version: ZedVersion,
}
```

**Features:**
- Tracks which users are connected
- Manages channel subscriptions
- Handles version compatibility
- Provides efficient broadcast mechanisms

### 3. Database Layer (`collab/src/db/`)

PostgreSQL-based persistence layer with SeaORM:

**Core Tables:**
- `channels` - Channel hierarchy and metadata
- `channel_members` - Membership and roles
- `channel_messages` - Persistent chat history
- `buffers` - Shared document state
- `rooms` - Voice/video call sessions
- `projects` - Shared project metadata

### 4. Protocol Layer (`proto/`)

Protocol Buffer definitions for all messages:

```protobuf
// Channel operations
message Channel {
    uint64 id = 1;
    string name = 2;
    ChannelVisibility visibility = 3;
    repeated uint64 parent_path = 4;
}

// Real-time updates
message UpdateChannels {
    repeated Channel channels = 1;
    repeated uint64 delete_channels = 2;
    repeated ChannelParticipants channel_participants = 3;
}
```

## Communication Protocol

### WebSocket-based RPC

All communication uses WebSocket with Protocol Buffer serialization:

1. **Connection Establishment**
   ```
   Client → Server: WebSocket Upgrade with Auth Token
   Server → Client: Connection Accepted + Initial State
   ```

2. **Message Flow**
   ```
   Client → Server: TypedEnvelope<RequestMessage>
   Server: Route to Handler
   Server → Client: TypedEnvelope<ResponseMessage>
   Server → Other Clients: Broadcast Updates
   ```

3. **Heartbeat/Keepalive**
   - Periodic ping/pong frames
   - Automatic reconnection on failure
   - State reconciliation after reconnect

### Message Types

**Request/Response Patterns:**
- `JoinChannel` → `JoinChannelResponse`
- `SendChannelMessage` → `SendChannelMessageResponse`
- `ShareProject` → `ShareProjectResponse`

**Broadcast Patterns:**
- `ChannelMessageSent` - New message to all participants
- `UpdateChannels` - Channel state changes
- `RoomUpdated` - Voice/video participant changes

## Channel System Deep Dive

### Channel Architecture

Channels in Zed are hierarchical, multi-purpose collaboration spaces:

```rust
pub struct Channel {
    pub id: ChannelId,
    pub name: String,
    pub visibility: ChannelVisibility,
    pub parent_path: String,  // Ancestry encoding
    pub requires_zed_cla: bool,
}

pub enum ChannelVisibility {
    Public,   // Visible to all members
    Members,  // Visible only to channel members
}
```

### Channel Features

1. **Hierarchical Organization**
   - Parent-child relationships
   - Path-based ancestry (`"1/5/12/"`)
   - Inherited permissions

2. **Multi-Modal Communication**
   - Text chat with rich formatting
   - Voice/video calls (rooms)
   - Shared buffers (collaborative editing)
   - Project sharing

3. **Role-Based Access Control**
   ```rust
   pub enum ChannelRole {
       Admin,   // Full control
       Member,  // Read/write access
       Talker,  // Voice + read access
       Guest,   // Read-only access
       Banned,  // No access
   }
   ```

### Channel Buffer Collaboration

Channels can have associated collaborative buffers:

```rust
// Real-time collaborative editing
message UpdateChannelBuffer {
    uint64 channel_id = 1;
    repeated Operation operations = 2;  // CRDTs
}

// Synchronization
message ChannelBufferVersion {
    uint64 channel_id = 1;
    repeated VectorClockEntry version = 2;
    uint64 epoch = 3;
}
```

**Conflict Resolution:**
- Operational Transformation (OT)
- Vector clocks for causality
- Epoch numbers for major resets

## Real-Time Collaboration Mechanisms

### 1. Project Sharing

Projects can be shared within rooms for real-time collaboration:

```rust
// Share project
async fn share_project(
    request: proto::ShareProject,
    response: Response<proto::ShareProject>,
    session: Session,
) -> Result<()> {
    let project_id = db.share_project(
        room_id,
        session.connection_id,
        &request.worktrees,
    ).await?;

    response.send(proto::ShareProjectResponse { project_id })?;
    room_updated(&room, &session.peer);
    Ok(())
}
```

**Features:**
- Multiple worktrees per project
- Real-time file system updates
- Shared language servers
- Collaborative editing

### 2. Voice/Video Calls (Rooms)

Integrated with LiveKit for WebRTC:

```rust
pub struct Room {
    pub id: RoomId,
    pub participants: Vec<Participant>,
    pub pending_participants: Vec<PendingParticipant>,
    pub live_kit_room: String,
}

pub struct Participant {
    pub user_id: UserId,
    pub peer_id: PeerId,
    pub projects: Vec<ParticipantProject>,
    pub location: ParticipantLocation,
    pub role: ChannelRole,
}
```

**Call Features:**
- Screen sharing
- Participant following
- Project context awareness
- Role-based permissions

### 3. Message Streaming

Real-time message delivery with ordering guarantees:

```rust
async fn send_channel_message(
    request: proto::SendChannelMessage,
    response: Response<proto::SendChannelMessage>,
    session: Session,
) -> Result<()> {
    // Validate and store message
    let message = db.create_channel_message(
        channel_id,
        user_id,
        &body,
        timestamp,
        nonce,
    ).await?;

    // Broadcast to participants
    broadcast(
        participant_connection_ids,
        proto::ChannelMessageSent { message },
    );

    // Notify non-participants of activity
    broadcast(
        non_participant_ids,
        proto::UpdateChannels { latest_message_ids },
    );

    Ok(())
}
```

## Security and Authentication

### Authentication Flow

1. **JWT-based Authentication**
   ```rust
   pub struct AccessTokenClaims {
       pub user_id: UserId,
       pub is_admin: bool,
       pub iat: u64,  // Issued at
       pub exp: u64,  // Expiration
   }
   ```

2. **Principal Types**
   ```rust
   pub enum Principal {
       User(User),
       Impersonated { user: User, admin: User },
   }
   ```

### Authorization Model

Channel access is determined by:
1. Direct membership
2. Parent channel membership (inheritance)
3. Public visibility settings
4. CLA requirements

```rust
impl ChannelRole {
    pub fn can_see_channel(&self, visibility: ChannelVisibility) -> bool {
        match self {
            Admin | Member => true,
            Guest | Talker => visibility == ChannelVisibility::Public,
            Banned => false,
        }
    }
}
```

### Data Security

- **Transport**: TLS 1.3 for all connections
- **Storage**: Encrypted at rest in PostgreSQL
- **Messages**: Optional end-to-end encryption
- **Tokens**: Short-lived with refresh mechanism

## Performance Optimizations

### 1. Connection Management

```rust
// Connection limits
const MAX_CONCURRENT_CONNECTIONS: usize = 50_000;

// Version compatibility for efficient protocols
impl ZedVersion {
    pub fn can_collaborate(&self) -> bool {
        self.0 >= SemanticVersion::new(0, 157, 0)
    }
}
```

### 2. Message Batching

High-frequency updates are batched:

```rust
// Buffer operations batched per frame
let mut operations = Vec::new();
while let Ok(op) = operation_rx.try_recv() {
    operations.push(op);
    if operations.len() >= MAX_BATCH_SIZE {
        break;
    }
}
send_operations_batch(operations);
```

### 3. Caching Strategies

- **Channel Hierarchy**: Cached in memory
- **User Permissions**: LRU cache with TTL
- **Message History**: Pagination with cursor
- **Project State**: Incremental updates only

### 4. Database Optimizations

```sql
-- Efficient channel descendant queries
CREATE INDEX idx_channels_parent_path ON channels
    USING gin (parent_path gin_trgm_ops);

-- Message pagination
CREATE INDEX idx_messages_channel_timestamp ON channel_messages
    (channel_id, sent_at DESC);
```

## Mobile Integration Considerations

### 1. Bandwidth Optimization

For mobile clients, consider:
- **Delta Compression**: Send only changes
- **Adaptive Quality**: Reduce update frequency on cellular
- **Selective Sync**: Subscribe to active channels only

### 2. Battery Efficiency

```rust
// Mobile-aware connection parameters
pub struct MobileConnectionConfig {
    pub keepalive_interval: Duration,     // Longer intervals
    pub reconnect_backoff: BackoffConfig, // Exponential backoff
    pub update_throttle: Duration,        // Limit update frequency
}
```

### 3. Offline Support

- **Message Queue**: Store-and-forward for outgoing
- **State Snapshot**: Periodic checkpoint saves
- **Conflict Resolution**: Last-write-wins with vector clocks

### 4. Protocol Extensions for Mobile

```protobuf
// Mobile-specific messages
message MobileConnectionInfo {
    NetworkType network_type = 1;
    BatteryLevel battery_level = 2;
    bool is_background = 3;
}

message ThrottledUpdate {
    uint64 channel_id = 1;
    uint32 pending_updates = 2;
    google.protobuf.Timestamp next_sync = 3;
}
```

## Future Considerations

### 1. Scalability Enhancements

- **Horizontal Scaling**: Multiple collab servers with coordination
- **Regional Deployment**: Edge servers for lower latency
- **Federation**: Cross-organization collaboration

### 2. Protocol Evolution

- **Version Negotiation**: Backward compatibility
- **Feature Flags**: Progressive enhancement
- **Extension Points**: Plugin architecture for custom features

### 3. Enhanced Security

- **Zero-Knowledge**: End-to-end encryption for sensitive projects
- **Audit Logging**: Compliance and forensics
- **MFA**: Multi-factor authentication support

## Conclusion

Zed's collaboration architecture is a sophisticated system that balances real-time performance with reliability and security. Its channel-based approach provides flexible collaboration primitives while the underlying RPC protocol ensures efficient communication. The architecture is well-positioned for mobile integration with appropriate optimizations for bandwidth and battery efficiency.

Key takeaways:
- **Channels** are the fundamental organizing principle
- **WebSocket + Protobuf** provides efficient real-time communication
- **Role-based access control** ensures security
- **Operational transformation** enables conflict-free collaboration
- **Modular design** allows for future extensions

For mobile integration, the existing protocol can be extended with mobile-specific optimizations while maintaining compatibility with the desktop client.
