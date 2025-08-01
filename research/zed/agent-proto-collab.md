# Agent Proto/Collab Architecture Gameplan

## Roadmap

- [x] **Phase 1**: Proto definitions and conversions (DONE - commit 264c3d93f4)
- [x] **Phase 2**: ThreadStore client integration (COMPLETED)
  - [x] Simple event forwarding without batching
  - [x] Basic proto conversions
  - [x] **Client connection management**
- [ ] **Phase 3**: Collab server handlers (CURRENT)
  - [ ] **Subscription management** ← **WE ARE HERE**
  - [ ] Event broadcasting
  - [ ] Security validation
- [ ] **Phase 4**: Mobile client implementation
  - [ ] Event stream handling
  - [ ] UI integration
- [ ] **Phase 5**: Performance optimization
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

### Phase 1: Client-Side Event Capture

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

### Phase 2: Server-Side Event Routing

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

#### 2.3 Event Broadcasting
```rust
async fn handle_agent_event_notification(
    notification: proto::AgentEventNotification,
    session: Session,
) -> Result<()> {
    let event = notification.event.context("missing event")?;
    let thread_id = ThreadId::from_proto(event.thread_id.context("missing thread_id")?);

    // Verify ownership
    let db = session.db().await;
    if !db.user_owns_thread(session.user_id(), thread_id).await? {
        return Err(anyhow!("unauthorized"));
    }

    // Broadcast to subscribed connections
    let connection_pool = session.connection_pool().await;
    for (conn_id, subscription) in &session.agent_subscriptions {
        if subscription.matches_thread(thread_id) {
            session.peer.send(*conn_id, notification.clone())?;
        }
    }

    Ok(())
}
```

### Phase 3: Mobile Client Integration

#### 3.1 Subscription Flow
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

### 1. Event Batching (Phase 5 - Future Optimization)
- **Phase 2**: All events sent immediately for simplicity
- **Phase 5**: Stream text events will be buffered for 50ms before sending
- Batching will reduce network overhead for rapid token generation
- Critical events will bypass batching when implemented

### 2. Subscription Model
- Explicit subscription required (unlike implicit channel membership)
- Can subscribe to specific threads or all user threads
- Subscriptions persist across reconnections

### 3. Security Model
- Thread ownership checked on every event
- No role-based permissions (simpler than channels)
- Events never cross user boundaries

### 4. State Synchronization
- `SubscribeToAgentEvents` returns recent events
- Supports resuming from last known event
- Full thread state available via `GetAgentThread`

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

### 1. Streaming Text Optimization (Phase 5)
```rust
// NOTE: This is planned for Phase 5. Phase 2 sends events immediately.
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

### 2. Connection Pool Efficiency
- Use same connection pool patterns as channels
- Broadcast to all user connections simultaneously
- Handle connection lifecycle automatically

### 3. Database Considerations
- Thread ownership queries should be indexed
- Consider caching ownership for active threads
- Event history retention policy needed

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

## Next Steps for Phase 2

1. **Complete proto conversions** in `agent/src/proto/mod.rs`
   - Focus on ThreadEvent → proto::ThreadEvent conversions
   - Implement essential types only (defer complex ones to Phase 3)

2. **Modify ThreadStore** to accept client reference
   - Add `client: Option<Arc<Client>>` field
   - Update constructor to accept client
   - Add subscription tracking

3. **Implement basic event forwarding**
   - Subscribe to thread events on creation
   - Convert events to proto format
   - Send via client without batching

4. **Test event flow**
   - Verify events are sent to server
   - Check proto serialization
   - Ensure no performance regression

**Note**: Keep Phase 2 simple - no batching, no complex optimizations. Focus on getting events flowing end-to-end.
