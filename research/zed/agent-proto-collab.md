# Agent Proto/Collab Architecture Gameplan

## Roadmap

- [x] **Phase 1**: Proto definitions and conversions (DONE - commit 264c3d93f4)
- [x] **Phase 2**: ThreadStore client integration (COMPLETED)
  - [x] Simple event forwarding without batching
  - [x] Basic proto conversions
  - [x] Client connection management
- [x] **Phase 3**: Collab server handlers (COMPLETED)
  - [x] **Subscription management**
  - [x] **Event broadcasting** 
  - [x] Security validation
- [ ] **Phase 4**: Database integration (CURRENT) ← **WE ARE HERE**
  - [ ] Event-driven database schema design
  - [ ] Agent thread and event storage
  - [ ] Subscription tracking in database
  - [ ] Migration utilities and testing
- [ ] **Phase 5**: Event broadcasting implementation
  - [ ] Real-time event delivery using database
  - [ ] Connection management and cleanup
  - [ ] Event history and catch-up mechanisms
- [ ] **Phase 6**: Mobile client implementation
  - [ ] Event stream handling
  - [ ] UI integration
- [ ] **Phase 7**: Performance optimization
  - [ ] Event batching for streaming text
  - [ ] Connection pooling optimizations
  - [ ] Caching and rate limiting

## Overview

This document outlines the architecture and implementation plan for integrating agent functionality into Zed's collaboration system, enabling real-time agent event streaming to mobile clients. Based on the patterns established by `UpdateChannels` and the proto definitions from commit 264c3d93f4.

## Goals

1. **Real-time Event Streaming**: Stream agent events (text generation, tool use, etc.) to mobile clients
2. **Efficient Broadcasting**: Use Zed's existing collab infrastructure for minimal latency
3. **Security**: Ensure users only see their own threads and events
4. **Resilience**: Handle disconnections and reconnections gracefully
5. **Event Queue Architecture**: Route events through centralized queue for database storage, real-time broadcast, and sync-replay
6. **Event Sourcing**: Enable state reconstruction via snapshot + event replay patterns

## Architecture Components

### 1. Proto Message Flow

```
┌─────────────┐      ThreadEvent      ┌─────────────┐     AgentEventNotification    ┌─────────────┐
│   Thread    │ ──────────────────> │ ThreadStore │ ────────────────────────────> │ Collab Server│
│   (GPUI)    │                     │             │                                │              │
└─────────────┘                     └─────────────┘                                └──────┬───────┘
                                                                                           │
                                                                                           │ Broadcast
                                                                                           ▼
                                                                                    ┌─────────────┐
                                                                                    │Mobile Client│
                                                                                    └─────────────┘
```

### 2. Message Types (Already Defined)

#### Core Messages
- `SubscribeToAgentEvents` / `SubscribeToAgentEventsResponse`
- `UnsubscribeFromAgentEvents` / `UnsubscribeFromAgentEventsResponse`
- `AgentEventNotification` (server → client push)

#### Thread Operations
- `GetAgentThreads` / `GetAgentThreadsResponse`
- `GetAgentThread` / `GetAgentThreadResponse`
- `CreateAgentThread` / `CreateAgentThreadResponse`
- `SendAgentMessage` / `SendAgentMessageResponse`

#### Tool Operations
- `UseAgentTools` / `UseAgentToolsResponse`
- `DenyAgentTools` / `DenyAgentToolsResponse`
- `CancelAgentCompletion` / `CancelAgentCompletionResponse`
- `RestoreThreadCheckpoint` / `RestoreThreadCheckpointResponse`

## Implementation Plan

### Phase 1: Client-Side Event Capture (COMPLETED)

#### 1.1 ThreadStore Enhancement
```rust
// Add to ThreadStore
pub struct ThreadStore {
    // ... existing fields
    client: Option<Arc<Client>>,
    thread_subscriptions: HashMap<ThreadId, Subscription>,
    event_buffer: HashMap<ThreadId, Vec<PendingEvent>>, // For batching
}

impl ThreadStore {
    pub fn initialize_with_client(&mut self, client: Arc<Client>, cx: &mut Context<Self>) {
        self.client = Some(client.clone());

        // Register for incoming notifications
        client.add_message_handler(cx.weak_entity(), Self::handle_agent_event_notification);
    }

    pub fn create_thread(&mut self, cx: &mut Context<Self>) -> Entity<Thread> {
        let thread = /* ... existing creation logic ... */;

        // Subscribe to thread events
        if self.client.is_some() {
            let subscription = cx.subscribe(&thread, |store, thread, event, cx| {
                store.on_thread_event(thread, event, cx);
            });
            self.thread_subscriptions.insert(thread.read(cx).id(), subscription);
        }

        thread
    }

    fn on_thread_event(&mut self, thread: Entity<Thread>, event: &ThreadEvent, cx: &mut Context<Self>) {
        if let Some(client) = &self.client {
            // Convert and send event
            self.forward_event_to_server(thread.read(cx).id(), event, cx);
        }
    }
}
```

#### 1.2 Event Forwarding Strategy (Phase 2 - Simple Implementation)
```rust
impl ThreadStore {
    fn forward_event_to_server(&mut self, thread_id: ThreadId, event: &ThreadEvent, cx: &mut Context<Self>) {
        // NOTE: Phase 2 - Send all events immediately without batching
        // Batching optimization will be added in Phase 5
        self.send_event_immediate(thread_id, event, cx);
    }

    fn send_event_immediate(&mut self, thread_id: ThreadId, event: &ThreadEvent, cx: &mut Context<Self>) {
        if let Some(client) = &self.client {
            // Convert ThreadEvent to proto
            let proto_event = proto::ThreadEvent::from(event);

            let notification = proto::AgentEventNotification {
                event: Some(proto::AgentEvent {
                    event_id: Uuid::new_v4().to_string(),
                    timestamp: Some(Timestamp::now()),
                    user_id: client.user_id().to_string(),
                    thread_id: Some(thread_id.into()),
                    event: Some(proto_event),
                }),
            };

            // Send to server
            cx.background_executor().spawn(async move {
                client.send(notification).log_err();
            }).detach();
        }
    }
}
```

### Phase 2: Server-Side Event Routing (COMPLETED)

#### 2.1 Handler Registration
```rust
// In collab/src/rpc.rs
server
    .add_request_handler(subscribe_to_agent_events)
    .add_request_handler(unsubscribe_from_agent_events)
    .add_request_handler(get_agent_threads)
    .add_request_handler(get_agent_thread)
    .add_request_handler(create_agent_thread)
    .add_request_handler(send_agent_message)
    .add_request_handler(cancel_agent_completion)
    .add_request_handler(use_agent_tools)
    .add_request_handler(deny_agent_tools)
    .add_request_handler(restore_thread_checkpoint)
    .add_message_handler(handle_agent_event_notification);
```

#### 2.2 Subscription Management
```rust
// Track agent event subscriptions per session
struct AgentSubscription {
    thread_filter: Option<ThreadId>,  // None = all threads
    last_event_id: Option<String>,
    subscribed_at: Instant,
}

impl Session {
    agent_subscriptions: HashMap<ConnectionId, AgentSubscription>,
}
```

#### 2.3 Event Broadcasting (Updated for Dual-Path Pattern)
```rust
async fn handle_agent_event_notification(
    notification: proto::AgentEventNotification,
    session: Session,
) -> Result<()> {
    let event = notification.event.context("missing event")?;
    let thread_id = ThreadId::from_proto(event.thread_id.context("missing thread_id")?);
    let user_id = UserId::from_proto(event.user_id);

    // Verify ownership
    let db = session.db().await;
    if !db.user_owns_thread(user_id, thread_id).await? {
        return Err(anyhow!("unauthorized"));
    }

    // EVENT QUEUE PATTERN: Route through centralized event queue
    
    // Send event to the centralized event queue
    // The queue will handle:
    // 1. Database storage for persistence
    // 2. Real-time broadcast to live clients  
    // 3. Sync-replay ordering and deduplication
    session.event_queue.enqueue_agent_event(
        thread_id,
        user_id,
        event.clone(),
    ).await?;

    Ok(())
}
```

### Phase 3: Database Integration (CURRENT)

#### 3.1 Database Schema Design
```sql
-- Agent threads table
CREATE TABLE agent_threads (
    id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    title TEXT,
    summary TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    archived BOOLEAN NOT NULL DEFAULT FALSE,
    profile_id TEXT,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Agent events table for real-time streaming and history
CREATE TABLE agent_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT UNIQUE NOT NULL,
    thread_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    event_data BLOB NOT NULL,  -- Serialized ThreadEvent proto
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (thread_id) REFERENCES agent_threads(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Agent subscriptions for tracking active listeners
CREATE TABLE agent_subscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    thread_id TEXT,  -- NULL for all-threads subscription
    subscribed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_event_id TEXT,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (thread_id) REFERENCES agent_threads(id) ON DELETE CASCADE,
    
    UNIQUE(connection_id, thread_id)  -- One subscription per connection per thread
);

-- Indexes for performance
CREATE INDEX idx_agent_events_thread_timestamp ON agent_events(thread_id, timestamp);
CREATE INDEX idx_agent_events_user_timestamp ON agent_events(user_id, timestamp);
CREATE INDEX idx_agent_subscriptions_user ON agent_subscriptions(user_id);
CREATE INDEX idx_agent_subscriptions_connection ON agent_subscriptions(connection_id);
```

#### 3.2 Database Access Layer
```rust
// collab/src/db/agent.rs
impl Database {
    pub async fn create_agent_thread(
        &self,
        user_id: UserId,
        title: Option<String>,
        profile_id: Option<String>,
    ) -> Result<ThreadId> {
        let thread_id = ThreadId::new();
        
        sqlx::query!(
            "INSERT INTO agent_threads (id, user_id, title, summary, profile_id)
             VALUES ($1, $2, $3, $4, $5)",
            thread_id.to_string(),
            user_id.0,
            title,
            "New conversation",  // Default summary
            profile_id
        )
        .execute(&self.pool)
        .await?;
        
        Ok(thread_id)
    }

    pub async fn store_agent_event(
        &self,
        event_id: String,
        thread_id: ThreadId,
        user_id: UserId,
        event: &proto::ThreadEvent,
    ) -> Result<()> {
        let event_data = prost::Message::encode_to_vec(event);
        let event_type = event_type_string(event);
        
        sqlx::query!(
            "INSERT INTO agent_events (event_id, thread_id, user_id, event_type, event_data)
             VALUES ($1, $2, $3, $4, $5)",
            event_id,
            thread_id.to_string(),
            user_id.0,
            event_type,
            event_data
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn get_agent_events_since(
        &self,
        thread_id: ThreadId,
        user_id: UserId,
        since_timestamp: Option<DateTime<Utc>>,
        limit: i32,
    ) -> Result<Vec<proto::AgentEvent>> {
        let since = since_timestamp.unwrap_or_else(|| Utc::now() - Duration::hours(24));
        
        let rows = sqlx::query!(
            "SELECT event_id, event_data, timestamp 
             FROM agent_events 
             WHERE thread_id = $1 AND user_id = $2 AND timestamp > $3
             ORDER BY timestamp ASC
             LIMIT $4",
            thread_id.to_string(),
            user_id.0,
            since,
            limit
        )
        .fetch_all(&self.pool)
        .await?;

        let mut events = Vec::new();
        for row in rows {
            let event_data: proto::ThreadEvent = prost::Message::decode(&row.event_data[..])?;
            events.push(proto::AgentEvent {
                event_id: row.event_id,
                timestamp: Some(timestamp_from_db(row.timestamp)),
                user_id: user_id.to_string(),
                thread_id: Some(thread_id.into()),
                event: Some(event_data),
            });
        }
        
        Ok(events)
    }

    pub async fn get_thread_snapshot_and_events(
        &self,
        thread_id: ThreadId,
        user_id: UserId,
        since_timestamp: Option<DateTime<Utc>>,
    ) -> Result<(proto::Thread, Vec<proto::AgentEvent>)> {
        // Event Sourcing Pattern: Snapshot + Event Replay
        
        // 1. Get thread snapshot (current state)
        let thread_snapshot = self.get_agent_thread(thread_id, user_id).await?;
        
        // 2. Get events since timestamp for replay
        let events = self.get_agent_events_since(thread_id, user_id, since_timestamp, 1000).await?;
        
        Ok((thread_snapshot, events))
    }

    pub async fn subscribe_to_agent_events(
        &self,
        connection_id: String,
        user_id: UserId,
        thread_id: Option<ThreadId>,
        last_event_id: Option<String>,
    ) -> Result<()> {
        sqlx::query!(
            "INSERT OR REPLACE INTO agent_subscriptions 
             (connection_id, user_id, thread_id, last_event_id)
             VALUES ($1, $2, $3, $4)",
            connection_id,
            user_id.0,
            thread_id.as_ref().map(|id| id.to_string()),
            last_event_id
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }

    pub async fn get_active_subscriptions(
        &self,
        thread_id: ThreadId,
    ) -> Result<Vec<String>> {
        let rows = sqlx::query!(
            "SELECT DISTINCT connection_id 
             FROM agent_subscriptions 
             WHERE thread_id = $1 OR thread_id IS NULL",
            thread_id.to_string()
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter().map(|row| row.connection_id).collect())
    }

    pub async fn cleanup_agent_subscriptions(
        &self,
        connection_id: &str,
    ) -> Result<()> {
        sqlx::query!(
            "DELETE FROM agent_subscriptions WHERE connection_id = $1",
            connection_id
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
}

fn event_type_string(event: &proto::ThreadEvent) -> String {
    match &event.event {
        Some(proto::thread_event::Event::ShowError(_)) => "show_error",
        Some(proto::thread_event::Event::StreamedCompletion(_)) => "streamed_completion",
        Some(proto::thread_event::Event::MessageAdded(_)) => "message_added",
        Some(proto::thread_event::Event::SummaryGenerated(_)) => "summary_generated",
        Some(proto::thread_event::Event::ToolUseLimitReached(_)) => "tool_use_limit_reached",
        // Add other event types as needed
        _ => "unknown",
    }.to_string()
}
```

#### 3.3 Migration Strategy
```rust
// migrations/20250102000000_add_agent_tables.sql
-- Migration for adding agent tables to existing collab database
-- This will be integrated into the collab migration system

-- Add the agent tables
-- (Schema from 3.1 above)

-- Migrate existing threads if any
-- This handles the case where mobile clients were storing threads locally
INSERT INTO agent_threads (id, user_id, title, summary, created_at, updated_at)
SELECT 
    thread_id,
    user_id,
    COALESCE(title, 'Imported Thread'),
    COALESCE(summary, 'Imported conversation'),
    created_at,
    updated_at
FROM legacy_agent_threads 
WHERE EXISTS (SELECT 1 FROM legacy_agent_threads);

-- Clean up legacy tables after successful migration
-- DROP TABLE IF EXISTS legacy_agent_threads;
```

### Phase 4: Dual-Path Event Handling (Database + Real-time)

#### 4.1 The Event Queue Pattern
The key architectural decision is handling events through a centralized event queue:

1. **Event Ingestion**: All events flow through a single event queue
2. **Database Persistence**: Queue workers store events for history and catch-up
3. **Real-time Broadcasting**: Queue workers send events to live connected clients
4. **Sync-Replay Support**: Queue ensures proper ordering and deduplication for state reconstruction

```rust
// collab/src/event_queue/mod.rs
pub struct AgentEventQueue {
    sender: mpsc::UnboundedSender<QueuedEvent>,
    db: Arc<Database>,
    connection_pool: Arc<ConnectionPool>,
}

struct QueuedEvent {
    event_id: String,
    thread_id: ThreadId,
    user_id: UserId,
    event: proto::ThreadEvent,
    timestamp: DateTime<Utc>,
    retry_count: u32,
}

impl AgentEventQueue {
    pub async fn enqueue_agent_event(
        &self,
        thread_id: ThreadId,
        user_id: UserId,
        event: proto::AgentEvent,
    ) -> Result<()> {
        let queued_event = QueuedEvent {
            event_id: event.event_id.clone(),
            thread_id,
            user_id,
            event: event.event.context("missing event data")?.clone(),
            timestamp: Utc::now(),
            retry_count: 0,
        };

        self.sender.send(queued_event)?;
        Ok(())
    }

    async fn process_events(&self) {
        let mut receiver = self.receiver.lock().await;
        
        while let Some(queued_event) = receiver.recv().await {
            // Process event through both paths concurrently
            let (store_result, broadcast_result) = tokio::join!(
                self.store_event(&queued_event),
                self.broadcast_event(&queued_event)
            );
            
            // Handle failures with retry logic
            if store_result.is_err() || broadcast_result.is_err() {
                self.handle_event_failure(queued_event).await;
            }
        }
    }

    async fn store_event(&self, event: &QueuedEvent) -> Result<()> {
        self.db.store_agent_event(
            event.event_id.clone(),
            event.thread_id,
            event.user_id,
            &event.event,
        ).await
    }

    async fn broadcast_event(&self, event: &QueuedEvent) -> Result<()> {
        let connection_ids = self.db.get_active_subscriptions(event.thread_id).await?;
        
        let notification = proto::AgentEventNotification {
            event: Some(proto::AgentEvent {
                event_id: event.event_id.clone(),
                timestamp: Some(timestamp_to_proto(event.timestamp)),
                user_id: event.user_id.to_string(),
                thread_id: Some(event.thread_id.into()),
                event: Some(event.event.clone()),
            }),
        };
        
        for connection_id in connection_ids {
            if let Some(peer_id) = self.connection_pool.get_peer_id(&connection_id) {
                // Non-blocking send - queue handles failures
                tokio::spawn({
                    let peer = self.peer.clone();
                    let notification = notification.clone();
                    async move {
                        peer.send(peer_id, notification).log_err();
                    }
                });
            }
        }
        
        Ok(())
    }
}

// collab/src/rpc/agent.rs  
async fn handle_agent_event_notification(
    notification: proto::AgentEventNotification,
    session: Session,
) -> Result<()> {
    let event = notification.event.context("missing event")?;
    let thread_id = ThreadId::from_proto(event.thread_id.context("missing thread_id")?);
    let user_id = UserId::from_proto(event.user_id);

    // Security check
    let db = session.db().await;
    if !db.user_owns_thread(user_id, thread_id).await? {
        return Err(anyhow!("unauthorized"));
    }

    // Route through event queue for processing
    session.event_queue.enqueue_agent_event(thread_id, user_id, event).await?;
    
    Ok(())
}
```

#### 4.2 Enhanced Subscription Management
```rust
async fn subscribe_to_agent_events(
    request: proto::SubscribeToAgentEvents,
    session: Session,
) -> Result<proto::SubscribeToAgentEventsResponse> {
    let user_id = session.user_id();
    let connection_id = session.connection_id().to_string();
    let thread_id = request.thread_id.map(ThreadId::from_proto);
    let since_timestamp = request.since_timestamp.map(timestamp_from_proto);

    let db = session.db().await;

    // Store subscription in database
    db.subscribe_to_agent_events(
        connection_id.clone(),
        user_id,
        thread_id,
        request.last_event_id,
    ).await?;

    // Get recent events for catch-up (Event Sourcing Pattern)
    let recent_events = if let Some(thread_id) = thread_id {
        db.get_agent_events_since(thread_id, user_id, since_timestamp, 50).await?
    } else {
        db.get_all_user_events_since(user_id, since_timestamp, 50).await?
    };

    // NOTE: For full state reconstruction, client can:
    // 1. Call GetAgentThread for snapshot at time T
    // 2. Call get_agent_events_since(T) to replay events since snapshot
    // 3. Apply events to reconstruct current state

    Ok(proto::SubscribeToAgentEventsResponse {
        success: true,
        error: None,
        recent_events,
    })
}
```

#### 4.3 Connection Lifecycle Management
```rust
// Automatic cleanup when connections close
impl Session {
    async fn on_connection_closed(&self, connection_id: &str) -> Result<()> {
        let db = self.db().await;
        
        // Clean up subscriptions for this connection
        db.cleanup_agent_subscriptions(connection_id).await?;
        
        Ok(())
    }
}
```

### Phase 5: Event Broadcasting Implementation (NEXT)

#### 5.1 Subscription Flow
```dart
class AgentEventService {
  StreamController<AgentEvent> _eventStream;

  Future<void> subscribeToThread(ThreadId threadId) async {
    final request = SubscribeToAgentEvents()
      ..threadId = threadId
      ..sinceTimestamp = _lastEventTimestamp;

    final response = await _rpcClient.request(request);

    // Process any recent events (Event Sourcing Pattern)
    for (final event in response.recentEvents) {
      _eventStream.add(event);
    }

    // Listen for new events
    _rpcClient.notifications
        .where((msg) => msg is AgentEventNotification)
        .where((msg) => msg.event.threadId == threadId)
        .listen((notification) => _eventStream.add(notification.event));
  }

  // Event Sourcing: Reconstruct thread state from snapshot + events
  Future<Thread> reconstructThreadState(ThreadId threadId, DateTime? since) async {
    final request = GetThreadSnapshotAndEvents()
      ..threadId = threadId
      ..sinceTimestamp = since?.toProto();

    final response = await _rpcClient.request(request);
    
    // Start with snapshot
    Thread thread = Thread.fromProto(response.threadSnapshot);
    
    // Apply events to reconstruct current state
    for (final event in response.events) {
      thread = thread.applyEvent(event);
    }
    
    return thread;
  }
}
```

### Phase 5: Mobile Client Integration

#### 5.1 Subscription Flow
```dart
class AgentEventService {
  StreamController<AgentEvent> _eventStream;

  Future<void> subscribeToThread(ThreadId threadId) async {
    final request = SubscribeToAgentEvents()
      ..threadId = threadId
      ..sinceTimestamp = _lastEventTimestamp;

    final response = await _rpcClient.request(request);

    // Process any recent events
    for (final event in response.recentEvents) {
      _eventStream.add(event);
    }

    // Listen for new events
    _rpcClient.notifications
        .where((msg) => msg is AgentEventNotification)
        .where((msg) => msg.event.threadId == threadId)
        .listen((notification) => _eventStream.add(notification.event));
  }
}
```

## Key Design Decisions

### 1. Event Queue Architecture ⭐ **CORE PATTERN**
- **Centralized Queue**: All events flow through a single event queue for processing
- **Database Path**: Queue workers store events for persistence, history, and catch-up
- **Real-time Path**: Queue workers broadcast events to live connections for minimal latency
- **Sync-Replay Support**: Queue ensures proper event ordering and deduplication for state reconstruction
- **Retry Logic**: Failed operations are retried with exponential backoff
- **Non-blocking**: Event ingestion never blocks - failures handled asynchronously
- **Implementation**: `event_queue.enqueue_agent_event()` → queue workers handle storage + broadcast

### 2. Event Sourcing & State Reconstruction ⭐ **CORE PATTERN**
- **Event Sourcing Pattern**: Thread state reconstructed from events rather than stored as snapshots
- **Snapshot + Replay**: Get thread snapshot at time T, then replay events since T to reconstruct current state
- **Efficient Sync**: Only transfer events since last known client state
- **Offline Support**: Clients cache snapshots and replay missed events on reconnect
- **Audit Trail**: Complete history of all thread changes preserved
- **Implementation**: `get_thread_snapshot_and_events()` + client-side `thread.applyEvent(event)`

### 3. Event Batching (Phase 7 - Future Optimization)
- **Current**: All events stored immediately for reliability
- **Phase 7**: Stream text events will be buffered for 50ms before sending
- Batching will reduce network overhead for rapid token generation
- Critical events will bypass batching when implemented

### 4. Subscription Model
- Explicit subscription required (unlike implicit channel membership)
- Can subscribe to specific threads or all user threads
- Subscriptions persist across reconnections via database storage
- Connection cleanup handled automatically on disconnect

### 5. Security Model
- Thread ownership checked on every event via database foreign keys
- No role-based permissions (simpler than channels)
- Events never cross user boundaries due to user_id constraints

### 6. State Synchronization Strategy
- **Real-time Updates**: Live clients receive events immediately via dual-path broadcasting
- **Catch-up Mechanism**: `SubscribeToAgentEvents` returns recent events from database
- **Resume Support**: Supports resuming from last known event via timestamps
- **Full State Queries**: `GetAgentThread` provides complete current state
- **Event History**: Maintained for replay and audit scenarios
- **Bandwidth Optimization**: Event sourcing avoids repeatedly sending full thread state

## Comparison with UpdateChannels

| Aspect | UpdateChannels | AgentEventNotification |
|--------|----------------|------------------------|
| Trigger | User actions (create, rename) | AI operations (streaming, tools) |
| Frequency | Low (user-driven) | High (token streaming) |
| Batching | Not needed | Critical for performance |
| Permissions | Role-based (admin, member) | Owner-only |
| State | Full state in each update | Event stream (incremental) |
| Subscription | Implicit (membership) | Explicit (subscribe call) |

## Performance Considerations

### 1. Event Queue Performance Optimization  
- **Asynchronous Processing**: Event queue decouples ingestion from processing for maximum throughput
- **Parallel Workers**: Database storage and real-time broadcast happen concurrently via queue workers
- **Non-blocking Ingestion**: Event submission never blocks - failures handled by retry logic
- **Batched Operations**: Queue can batch database writes for efficiency (Phase 7 optimization)
- **Indexed Queries**: Fast thread ownership and event retrieval
- **Connection Pool Efficiency**: Reuse existing collab connection infrastructure
- **Event History**: Configurable retention policy (default: 30 days)
- **Subscription Cleanup**: Automatic cleanup on connection close

### 2. Streaming Text Optimization (Phase 7)
```rust
// NOTE: This is planned for Phase 7. Current implementation stores events immediately.
struct StreamingBuffer {
    thread_id: ThreadId,
    chunks: Vec<String>,
    last_flush: Instant,
    flush_interval: Duration, // 50ms
}

impl StreamingBuffer {
    fn should_flush(&self) -> bool {
        self.last_flush.elapsed() > self.flush_interval ||
        self.chunks.join("").len() > 1024  // 1KB limit
    }
}
```

### 3. Connection Pool Efficiency
- Use same connection pool patterns as channels
- Database-driven subscription tracking
- Automatic cleanup of stale subscriptions
- Handle connection lifecycle via subscription table

## Testing Strategy

### 1. Unit Tests
- Proto conversion round-trips
- Event batching logic
- Subscription filtering

### 2. Integration Tests
- End-to-end event flow
- Reconnection handling
- Multi-client scenarios

### 3. Performance Tests
- High-frequency streaming
- Large thread counts
- Network interruption recovery

## Success Metrics

- Event latency < 100ms (local network)
- Support 100+ events/second per thread
- Zero event loss during reconnections
- Minimal CPU/memory overhead

## Next Steps for Phase 4 (Database Integration)

1. **Design and implement database schema**
   - Create migration files for agent tables
   - Add foreign key constraints for data integrity
   - Design indexes for optimal query performance

2. **Implement database access layer**
   - Add agent-specific database methods to collab/src/db
   - Implement event storage and retrieval functions
   - Add subscription management methods

3. **Create migration utilities**
   - Handle existing thread data migration
   - Add database version checks
   - Test migration rollback scenarios

4. **Implement event queue system**
   - Create `AgentEventQueue` with worker processing
   - Update `handle_agent_event_notification` to use event queue
   - Implement queue workers for storage + broadcast
   - Add retry logic and failure handling
   - Test queue performance and reliability

5. **Add comprehensive testing**
   - Unit tests for database operations and real-time broadcasting
   - Integration tests for dual-path event flow
   - Performance tests for concurrent storage + broadcast
   - Test failure scenarios (database down, network issues)
   - Test subscription cleanup on connection loss

6. **Update server handlers to use event queue pattern**
   - Modify existing handlers to route events through queue
   - Update subscription management with database backing  
   - Add event history retrieval for catch-up and sync-replay scenarios
   - Implement connection cleanup automation
   - Add queue monitoring and metrics

**Goal**: Establish event queue foundation that handles persistence, real-time broadcast, and sync-replay seamlessly.
