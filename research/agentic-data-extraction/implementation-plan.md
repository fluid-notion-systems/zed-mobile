# Implementation Plan: Agent Events via Collab Server

## Overview

This implementation plan outlines how to integrate Zed's agent system with the collaboration server to enable real-time agent event streaming to mobile and other clients. This approach leverages existing infrastructure rather than creating a separate WebSocket bridge.

## Current Status

### ✅ Completed Items

1. **PODO Extraction (`zed-agent-core` crate)** - DONE
   - Created standalone crate with core types
   - Implemented Thread, Message, MessageSegment, AgentEvent
   - Added EventBus for local event distribution
   - No GPUI dependencies

2. **Zed Agent Integration** - DONE
   - Added `core_conversion.rs` for GPUI ↔ Core conversions
   - Implemented `event_bridge.rs` to connect GPUI events to EventBus
   - Agent now uses EventBus for event emission

3. **Event System** - DONE
   - EventBus implemented in `zed-agent-core`
   - EventBridge connects GPUI events to core events
   - Conversion methods for all major event types

### 🚧 Next Steps

## 1. Collab Server Integration

### 1.1 Proto Definitions

Create `proto/agent.proto` with agent-specific messages:

```protobuf
message AgentThread {
    string id = 1;
    string title = 2;
    repeated string message_ids = 3;
    optional string profile_id = 4;
    google.protobuf.Timestamp created_at = 5;
    google.protobuf.Timestamp updated_at = 6;
    ThreadStatus status = 7;
    TokenUsage token_usage = 8;
}

message AgentEvent {
    google.protobuf.Timestamp timestamp = 1;
    string user_id = 2;
    
    oneof event {
        ThreadCreated thread_created = 10;
        ThreadUpdated thread_updated = 11;
        MessageAdded message_added = 12;
        MessageStreaming message_streaming = 13;
        ToolUseStarted tool_use_started = 14;
        ToolUseCompleted tool_use_completed = 15;
    }
}

// RPC messages
message SubscribeToAgentEvents {
    optional string thread_id = 1;
    bool include_history = 2;
}

message AgentEventNotification {
    AgentEvent event = 1;
}
```

### 1.2 Collab Server Extensions

Add to `collab/src/rpc.rs`:

```rust
impl Server {
    pub fn new() -> Arc<Self> {
        // ... existing handlers ...
        
        // Agent handlers
        server
            .add_request_handler(subscribe_to_agent_events)
            .add_request_handler(unsubscribe_from_agent_events)
            .add_request_handler(get_agent_threads)
            .add_request_handler(get_agent_thread)
            .add_message_handler(handle_agent_event_from_host)
    }
}
```

### 1.3 Agent Event Broadcasting

Create `collab/src/agent/subscriptions.rs`:

```rust
pub struct AgentSubscriptions {
    global_subscribers: HashMap<UserId, HashSet<ConnectionId>>,
    thread_subscribers: HashMap<String, HashSet<ConnectionId>>,
    connection_threads: HashMap<ConnectionId, HashSet<String>>,
}
```

## 2. Implementation Phases

### Phase 1: Proto & Infrastructure (Week 1) ⏳ CURRENT
- [ ] Define proto messages for agent events
- [ ] Generate Rust code from protos
- [ ] Add RPC handler stubs
- [ ] Set up subscription management structure

### Phase 2: Server Integration (Week 2)
- [ ] Implement agent subscription management
- [ ] Add event routing logic
- [ ] Handle connection lifecycle (cleanup on disconnect)
- [ ] Add authentication/authorization checks

### Phase 3: Desktop Client Integration (Week 3)
- [ ] Create `AgentCollabBridge` to connect EventBus to collab
- [ ] Convert core events to proto format
- [ ] Send events through collab connection
- [ ] Test end-to-end event flow

### Phase 4: Mobile Client (Week 4)
- [ ] Implement RPC client for agent events
- [ ] Build subscription management
- [ ] Create UI for agent panel
- [ ] Handle reconnection logic

## 3. Technical Details

### 3.1 Event Flow Architecture

```
Zed Desktop (Agent Action)
    ↓
GPUI Event
    ↓
EventBridge (event_bridge.rs)
    ↓
zed-agent-core EventBus
    ↓
AgentCollabBridge (NEW)
    ↓
Proto Conversion
    ↓
Collab Server (RPC)
    ↓
Mobile Client
```

### 3.2 AgentCollabBridge Implementation

```rust
pub struct AgentCollabBridge {
    client: Arc<Client>,
    event_bus: Model<EventBus>,
    _subscription: Subscription,
}

impl AgentCollabBridge {
    pub fn new(client: Arc<Client>, event_bus: Model<EventBus>, cx: &mut Context) -> Self {
        let subscription = event_bus.subscribe("collab_bridge", {
            let client = client.clone();
            move |event| {
                if let Some(proto_event) = event.to_proto() {
                    client.send(proto_event).trace_err();
                }
            }
        });
        
        Self {
            client,
            event_bus,
            _subscription: subscription,
        }
    }
}
```

### 3.3 Mobile Client Subscription

```dart
class AgentEventService {
  final RpcClient _rpcClient;
  
  Future<void> subscribeToEvents() async {
    final request = SubscribeToAgentEvents()
      ..includeHistory = true;
      
    final response = await _rpcClient.request(request);
    
    _rpcClient.notifications
        .where((msg) => msg is AgentEventNotification)
        .listen((notification) {
          _handleAgentEvent(notification.event);
        });
  }
}
```

## 4. Security Considerations

### Authentication
- Only authenticated users can subscribe to their own agent events
- Thread ownership validation before sending events
- Rate limiting to prevent event spam

### Data Privacy
- No agent data persisted on collab server
- Events are pass-through only
- TLS for all connections

## 5. Performance Considerations

### Event Batching
- Batch high-frequency events (streaming)
- Configurable flush intervals
- Maximum batch sizes

### Connection Management
- Heartbeat for connection health
- Automatic reconnection with backoff
- State synchronization on reconnect

## 6. Testing Strategy

### Unit Tests
- Subscription management logic
- Event routing correctness
- Proto conversion accuracy

### Integration Tests
- End-to-end event flow
- Disconnection handling
- Multi-client scenarios

### Load Tests
- High event frequency handling
- Multiple concurrent subscribers
- Network failure resilience

## 7. Success Criteria

1. **Functionality**
   - [ ] Agent events stream in real-time to mobile
   - [ ] All event types properly converted and transmitted
   - [ ] Reliable delivery with disconnection handling

2. **Performance**
   - [ ] Sub-100ms latency for local networks
   - [ ] Handles 1000+ events/second
   - [ ] Minimal CPU/memory overhead

3. **Security**
   - [ ] Users only see their own agent events
   - [ ] No data leakage between users
   - [ ] Secure authentication flow

## 8. Rollout Plan

### Stage 1: Internal Testing
- Deploy to staging environment
- Test with internal team
- Monitor performance metrics

### Stage 2: Beta Release
- Feature flag for select users
- Gather feedback on mobile experience
- Iterate on performance

### Stage 3: General Availability
- Enable for all users
- Documentation and examples
- Monitor adoption metrics

## 9. Future Enhancements

1. **Persistent History**
   - Optional event storage
   - Query historical events
   - Replay capabilities

2. **Advanced Features**
   - Event filtering by type
   - Compression for large events
   - WebTransport for lower latency

3. **Multi-Device Sync**
   - Sync agent state across devices
   - Collaborative agent sessions
   - Handoff between devices

## 10. Conclusion

This approach leverages Zed's existing collaboration infrastructure to provide agent event streaming without creating new systems. By using the collab server, we get:

- Unified connection management
- Existing authentication/authorization
- Battle-tested RPC protocol
- Better battery life on mobile (single connection)

The phased implementation allows for incremental development and testing, ensuring a stable and performant solution.