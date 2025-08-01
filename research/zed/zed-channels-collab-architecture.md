# Zed Channels Collab Architecture Analysis

## Overview

This document analyzes how the Zed collaboration server handles channels, including database operations, event firing, broadcasting patterns, and overall architecture. This analysis serves as a reference for implementing the agent event system using similar patterns.

## Key Components

### 1. Database Layer (`collab/src/db/queries/channels.rs`)

#### Channel Structure
```rust
pub struct Channel {
    pub id: ChannelId,
    pub name: String,
    pub visibility: ChannelVisibility,
    pub parent_path: Vec<ChannelId>,  // Hierarchical structure
    pub channel_order: i32,
}
```

#### Core Database Operations

**Channel Creation:**
```rust
pub async fn create_channel(
    &self,
    name: &str,
    parent_channel_id: Option<ChannelId>,
    admin_id: UserId,
) -> Result<(channel::Model, Option<channel_member::Model>)>
```

**Channel Management:**
- `join_channel()` - User joins a channel with role-based access
- `set_channel_visibility()` - Updates visibility (Public/Members)
- `invite_channel_member()` - Sends invitations with notifications
- `remove_channel_member()` - Removes users and cleans up subscriptions

#### Database Schema Patterns
```sql
-- Channels table (implied from code)
CREATE TABLE channels (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    visibility INTEGER NOT NULL,  -- Public/Members enum
    parent_path TEXT,  -- Hierarchical path storage
    channel_order INTEGER NOT NULL,
    requires_zed_cla BOOLEAN
);

-- Channel memberships with roles
CREATE TABLE channel_members (
    id INTEGER PRIMARY KEY,
    channel_id INTEGER REFERENCES channels(id),
    user_id INTEGER REFERENCES users(id),
    accepted BOOLEAN NOT NULL,
    role INTEGER NOT NULL  -- Admin/Member/Guest/Banned enum
);
```

### 2. RPC Layer (`collab/src/rpc.rs`)

#### Handler Registration Pattern
```rust
impl Server {
    pub fn new() -> Arc<Self> {
        server
            .add_request_handler(create_channel)
            .add_request_handler(delete_channel)
            .add_request_handler(invite_channel_member)
            .add_request_handler(set_channel_visibility)
            .add_request_handler(rename_channel)
            .add_request_handler(move_channel)
            .add_message_handler(subscribe_to_channels)
            // ... more handlers
    }
}
```

#### Event Broadcasting Architecture

**The UpdateChannels Pattern:**
```rust
pub struct UpdateChannels {
    repeated Channel channels = 1;                    // Channel updates
    repeated uint64 delete_channels = 4;              // Channel deletions  
    repeated Channel channel_invitations = 5;         // New invitations
    repeated uint64 remove_channel_invitations = 6;   // Cancelled invitations
    repeated ChannelParticipants channel_participants = 7;  // Active users
    repeated ChannelMessageId latest_channel_message_ids = 8;  // Chat updates
    repeated ChannelBufferVersion latest_channel_buffer_versions = 9;  // Buffer state
}
```

### 3. Event Broadcasting Patterns

#### Pattern 1: Direct Database → Broadcast
```rust
async fn create_channel(
    request: proto::CreateChannel,
    response: Response<proto::CreateChannel>,
    session: Session,
) -> Result<()> {
    let db = session.db().await;
    
    // 1. Database operation
    let (channel, membership) = db
        .create_channel(&request.name, parent_id, session.user_id())
        .await?;
    
    // 2. Response to requester
    response.send(proto::CreateChannelResponse {
        channel: Some(channel.to_proto()),
        parent_id: request.parent_id,
    })?;
    
    // 3. Broadcast to relevant connections
    let mut connection_pool = session.connection_pool().await;
    for (connection_id, role) in connection_pool.channel_connection_ids(root_id) {
        if !role.can_see_channel(channel.visibility) {
            continue;  // Permission-based filtering
        }

        let update = proto::UpdateChannels {
            channels: vec![channel.to_proto()],
            ..Default::default()
        };
        session.peer.send(connection_id, update.clone())?;
    }
    
    Ok(())
}
```

#### Pattern 2: Complex Multi-Step Broadcasting
```rust
async fn send_channel_message(
    request: proto::SendChannelMessage,
    response: Response<proto::SendChannelMessage>,  
    session: Session,
) -> Result<()> {
    // 1. Database operation returns broadcast info
    let CreatedChannelMessage {
        message_id,
        participant_connection_ids,  // Who should get full message
        notifications,
    } = session.db().await.create_channel_message(...).await?;
    
    // 2. Send full message to participants
    broadcast(
        Some(session.connection_id),
        participant_connection_ids.clone(),
        |connection| {
            session.peer.send(connection, proto::ChannelMessageSent {
                channel_id: channel_id.to_proto(),
                message: Some(message.clone()),
            })
        },
    );
    
    // 3. Send lightweight notification to non-participants
    let non_participants = pool.channel_connection_ids(channel_id)
        .filter_map(|(connection_id, _)| {
            if participant_connection_ids.contains(&connection_id) {
                None
            } else {
                Some(connection_id)
            }
        });
        
    broadcast(None, non_participants, |peer_id| {
        session.peer.send(peer_id, proto::UpdateChannels {
            latest_channel_message_ids: vec![proto::ChannelMessageId {
                channel_id: channel_id.to_proto(),
                message_id: message_id.to_proto(),
            }],
            ..Default::default()
        })
    });
    
    // 4. Send push notifications
    send_notifications(pool, &session.peer, notifications);
    
    Ok(())
}
```

### 4. Connection Pool Management

#### Subscription Tracking
```rust
pub struct ConnectionPool {
    // Maps user_id -> set of connection_ids
    user_connections: HashMap<UserId, HashSet<ConnectionId>>,
    
    // Maps channel_id -> map of (connection_id -> role)
    channel_connections: HashMap<ChannelId, HashMap<ConnectionId, ChannelRole>>,
}

impl ConnectionPool {
    // Get all connections subscribed to a channel
    pub fn channel_connection_ids(&self, channel_id: ChannelId) 
        -> impl Iterator<Item = (ConnectionId, ChannelRole)>;
        
    // Subscribe user to channel with role
    pub fn subscribe_to_channel(&mut self, user_id: UserId, channel_id: ChannelId, role: ChannelRole);
    
    // Cleanup on disconnect
    pub fn unsubscribe_from_channel(&mut self, user_id: &UserId, channel_id: &ChannelId);
}
```

#### Permission-Based Broadcasting
```rust
for (connection_id, role) in connection_pool.channel_connection_ids(root_id) {
    if !role.can_see_channel(channel.visibility) {
        continue;  // Skip connections without permission
    }
    
    let update = if role.can_see_channel(channel.visibility) {
        proto::UpdateChannels {
            channels: vec![channel.to_proto()],
            ..Default::default()
        }
    } else {
        proto::UpdateChannels {
            delete_channels: vec![channel.id.to_proto()],
            ..Default::default()
        }
    };
    
    session.peer.send(connection_id, update)?;
}
```

### 5. Notification System Integration

#### Notification Types
```rust
pub enum Notification {
    ChannelInvitation {
        channel_id: u64,
        channel_name: String,
        inviter_id: u64,
    },
    // ... other notification types
}
```

#### Notification Creation & Broadcasting
```rust
// Database creates notification
let notifications = self.create_notification(
    invitee_id,
    rpc::Notification::ChannelInvitation {
        channel_id: channel_id.to_proto(),
        channel_name: channel.name.clone(),
        inviter_id: inviter_id.to_proto(),
    },
    true,  // should_send_email
    &tx,
).await?;

// Send notifications to all user connections
send_notifications(pool, &session.peer, notifications);
```

## Key Architectural Patterns

### 1. **Immediate Database + Broadcast Pattern**
- Database operation completes first
- Success response sent to requester  
- Broadcast to relevant connections happens after
- No event queue - direct broadcasting

### 2. **Multiplexed Update Messages**
- Single `UpdateChannels` message carries multiple update types
- Reduces number of message handlers needed
- Efficient network usage
- Clients merge updates into local state

### 3. **Permission-Based Connection Filtering**
- Connection pool tracks user roles per channel
- Broadcasting includes permission checks
- Different messages based on user permissions
- Automatic cleanup on role changes

### 4. **Database-Driven Connection Management**
- Database operations return connection lists for broadcasting
- `participant_connection_ids` returned from operations
- Database knows who should receive what updates
- Clean separation between data and networking layers

### 5. **Differentiated Message Types**
- Full data for direct participants (`ChannelMessageSent`)
- Lightweight notifications for observers (`UpdateChannels`)
- Push notifications for offline users
- Optimized bandwidth usage

## Comparison with Agent Event Requirements

### Similarities
- **Real-time broadcasting** to subscribed connections
- **Permission-based filtering** (user can only see own threads)
- **Multiplexed updates** in single message types
- **Database-driven operations** with immediate broadcasting

### Differences
- **Event frequency**: Channels are low-frequency, agents are high-frequency
- **Event types**: Channel CRUD vs streaming text/tool use
- **State model**: Channels use full state updates, agents need event streams
- **Persistence**: Channels persist indefinitely, agent events may have retention policies

## Implementation Guidance for Agent Events

### Recommended Architecture

#### 1. **Database Schema** (Following Channel Patterns)
```sql
-- Agent threads (similar to channels table)
CREATE TABLE agent_threads (
    id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    title TEXT,
    summary TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    profile_id TEXT
);

-- Agent events (new - channels don't have event history)
CREATE TABLE agent_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT UNIQUE NOT NULL,
    thread_id TEXT NOT NULL REFERENCES agent_threads(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    event_type TEXT NOT NULL,
    event_data BLOB NOT NULL,  -- Serialized proto
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Agent subscriptions (similar to channel connection tracking)
CREATE TABLE agent_subscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id TEXT NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users(id),
    thread_id TEXT REFERENCES agent_threads(id),  -- NULL for all-threads
    subscribed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_event_id TEXT
);
```

#### 2. **RPC Handler Pattern** (Following Channel Patterns)
```rust
// Register handlers similar to channels
server
    .add_request_handler(subscribe_to_agent_events)
    .add_request_handler(get_agent_threads)
    .add_request_handler(create_agent_thread)
    .add_message_handler(handle_agent_event_notification);

async fn handle_agent_event_notification(
    notification: proto::AgentEventNotification,
    session: Session,
) -> Result<()> {
    let event = notification.event.context("missing event")?;
    let thread_id = ThreadId::from_proto(event.thread_id.context("missing thread_id")?);
    let user_id = UserId::from_proto(event.user_id);

    // 1. Security check (like channels)
    let db = session.db().await;
    if !db.user_owns_thread(user_id, thread_id).await? {
        return Err(anyhow!("unauthorized"));
    }

    // 2. Store in database (new for agents)
    db.store_agent_event(
        event.event_id.clone(),
        thread_id,
        user_id,
        &event.event.context("missing event data")?,
    ).await?;

    // 3. Broadcast to subscribed connections (like channels)
    let connection_pool = session.connection_pool().await;
    let subscriptions = db.get_active_subscriptions(thread_id).await?;
    
    for connection_id in subscriptions {
        if let Some(peer_id) = connection_pool.get_peer_id(&connection_id) {
            session.peer.send(peer_id, notification.clone())?;
        }
    }

    Ok(())
}
```

#### 3. **Event Broadcasting Pattern** (Extended from Channels)
```rust
// Similar to UpdateChannels, but for agent events
message AgentEventNotification {
    AgentEvent event = 1;
}

message AgentEvent {
    string event_id = 1;
    Timestamp timestamp = 2;
    string user_id = 3;
    ThreadId thread_id = 4;
    ThreadEvent event = 5;  // The actual event data
}
```

### Key Adaptations for Agents

1. **Event History Storage**: Unlike channels, agents need event history for replay
2. **High-Frequency Optimization**: Consider batching for streaming text events  
3. **Subscription Management**: Per-thread subscriptions instead of per-channel
4. **Security Model**: Owner-only access (simpler than channel roles)
5. **Event Queue**: Consider adding queue for reliability (channels broadcast directly)

## Conclusion

The Zed channels architecture provides an excellent foundation for agent events:

- **Proven patterns** for real-time collaboration
- **Scalable broadcasting** with permission filtering  
- **Database-driven design** with immediate consistency
- **Clean separation** between data and networking layers

The main adaptations needed are:
- Adding event history storage for replay capability
- Implementing subscription management for threads
- Adding event queue for high-frequency stream reliability
- Optimizing for the unique characteristics of agent interactions

The core patterns of immediate database operations followed by permission-based broadcasting can be directly applied to the agent event system.