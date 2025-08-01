# Agent Collaboration Integration Guide

## Overview

This guide details how to integrate Zed's agent system with the collaboration server to enable real-time agent event streaming to mobile and other clients. The integration leverages the existing RPC infrastructure to provide a unified communication channel for all collaboration features.

## Goals

1. **Real-time Synchronization**: Stream agent events as they happen
2. **Minimal Latency**: Sub-100ms event delivery on local networks
3. **Scalability**: Support multiple simultaneous subscribers
4. **Security**: Ensure users only see their own agent data
5. **Compatibility**: Work with both cloud and local deployments

## Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Zed Desktop │────▶│ Collab Server│────▶│   Mobile    │
│   (Agent)   │     │  (RPC Relay) │     │   Client    │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                     │
       └────────────────────┴─────────────────────┘
                    Agent Events Flow
```

## Proto Definitions

### 1. Core Agent Messages

Create `proto/agent.proto`:

```protobuf
syntax = "proto3";

package zed.agent;

import "google/protobuf/timestamp.proto";

// Core data structures
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

message AgentMessage {
    string id = 1;
    string thread_id = 2;
    MessageRole role = 3;
    repeated MessageSegment segments = 4;
    google.protobuf.Timestamp timestamp = 5;
    MessageStatus status = 6;
}

message MessageSegment {
    oneof content {
        TextSegment text = 1;
        ToolUseSegment tool_use = 2;
        ImageSegment image = 3;
    }
}

message TextSegment {
    string text = 1;
}

message ToolUseSegment {
    string tool_name = 1;
    string tool_id = 2;
    map<string, string> parameters = 3;
    optional string result = 4;
    ToolStatus status = 5;
}

message ImageSegment {
    bytes data = 1;
    string mime_type = 2;
    string alt_text = 3;
}

message TokenUsage {
    int32 input_tokens = 1;
    int32 output_tokens = 2;
    int32 total_tokens = 3;
    double estimated_cost = 4;
}

// Enums
enum ThreadStatus {
    THREAD_STATUS_UNSPECIFIED = 0;
    THREAD_STATUS_ACTIVE = 1;
    THREAD_STATUS_IDLE = 2;
    THREAD_STATUS_ARCHIVED = 3;
}

enum MessageRole {
    MESSAGE_ROLE_UNSPECIFIED = 0;
    MESSAGE_ROLE_USER = 1;
    MESSAGE_ROLE_ASSISTANT = 2;
    MESSAGE_ROLE_SYSTEM = 3;
}

enum MessageStatus {
    MESSAGE_STATUS_UNSPECIFIED = 0;
    MESSAGE_STATUS_PENDING = 1;
    MESSAGE_STATUS_STREAMING = 2;
    MESSAGE_STATUS_COMPLETE = 3;
    MESSAGE_STATUS_ERROR = 4;
}

enum ToolStatus {
    TOOL_STATUS_UNSPECIFIED = 0;
    TOOL_STATUS_PENDING = 1;
    TOOL_STATUS_RUNNING = 2;
    TOOL_STATUS_COMPLETE = 3;
    TOOL_STATUS_ERROR = 4;
}
```

### 2. Event Messages

```protobuf
// Event types
message ThreadCreated {
    AgentThread thread = 1;
}

message ThreadUpdated {
    string thread_id = 1;
    optional string title = 2;
    optional ThreadStatus status = 3;
}

message MessageAdded {
    AgentMessage message = 1;
}

message MessageStreaming {
    string message_id = 1;
    string thread_id = 2;
    MessageSegment segment = 3;
    bool is_final = 4;
}

message ToolUseStarted {
    string message_id = 1;
    string thread_id = 2;
    string tool_id = 3;
    string tool_name = 4;
    map<string, string> parameters = 5;
}

message ToolUseCompleted {
    string message_id = 1;
    string thread_id = 2;
    string tool_id = 3;
    optional string result = 4;
    optional string error = 5;
}

// Event wrapper
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
```

### 3. RPC Messages

```protobuf
// RPC request/response messages
message SubscribeToAgentEvents {
    optional string thread_id = 1;  // Subscribe to specific thread or all
    bool include_history = 2;       // Send recent events on subscribe
}

message SubscribeToAgentEventsResponse {
    bool success = 1;
    optional string error = 2;
    repeated AgentEvent recent_events = 3;  // If include_history was true
}

message UnsubscribeFromAgentEvents {
    optional string thread_id = 1;
}

message UnsubscribeFromAgentEventsResponse {
    bool success = 1;
}

message AgentEventNotification {
    AgentEvent event = 1;
}

message GetAgentThreads {
    int32 limit = 1;
    int32 offset = 2;
    bool include_archived = 3;
}

message GetAgentThreadsResponse {
    repeated AgentThread threads = 1;
    int32 total_count = 2;
}

message GetAgentThread {
    string thread_id = 1;
    bool include_messages = 2;
    int32 message_limit = 3;
}

message GetAgentThreadResponse {
    optional AgentThread thread = 1;
    repeated AgentMessage messages = 2;
}

// Commands from mobile to agent
message SendAgentCommand {
    string thread_id = 1;
    string command = 2;
    map<string, string> parameters = 3;
}

message SendAgentCommandResponse {
    bool success = 1;
    optional string error = 2;
    optional string command_id = 3;
}
```

## Server Implementation

### 1. Agent Subscription Management

Create `collab/src/agent/subscriptions.rs`:

```rust
use collections::{HashMap, HashSet};
use rpc::{ConnectionId, proto};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Default)]
pub struct AgentSubscriptions {
    // User ID -> Set of connection IDs interested in all agent events
    global_subscribers: HashMap<UserId, HashSet<ConnectionId>>,
    // Thread ID -> Set of connection IDs interested in specific thread
    thread_subscribers: HashMap<String, HashSet<ConnectionId>>,
    // Connection ID -> Set of thread IDs (for cleanup)
    connection_threads: HashMap<ConnectionId, HashSet<String>>,
}

impl AgentSubscriptions {
    pub async fn subscribe_global(
        &mut self,
        user_id: UserId,
        connection_id: ConnectionId,
    ) {
        self.global_subscribers
            .entry(user_id)
            .or_default()
            .insert(connection_id);
    }
    
    pub async fn subscribe_thread(
        &mut self,
        thread_id: String,
        connection_id: ConnectionId,
    ) {
        self.thread_subscribers
            .entry(thread_id.clone())
            .or_default()
            .insert(connection_id);
            
        self.connection_threads
            .entry(connection_id)
            .or_default()
            .insert(thread_id);
    }
    
    pub async fn unsubscribe_all(&mut self, connection_id: ConnectionId) {
        // Remove from global subscribers
        for subscribers in self.global_subscribers.values_mut() {
            subscribers.remove(&connection_id);
        }
        
        // Remove from thread subscribers
        if let Some(threads) = self.connection_threads.remove(&connection_id) {
            for thread_id in threads {
                if let Some(subscribers) = self.thread_subscribers.get_mut(&thread_id) {
                    subscribers.remove(&connection_id);
                }
            }
        }
    }
    
    pub async fn get_recipients(
        &self,
        user_id: UserId,
        thread_id: Option<&str>,
    ) -> HashSet<ConnectionId> {
        let mut recipients = HashSet::new();
        
        // Add global subscribers for this user
        if let Some(global) = self.global_subscribers.get(&user_id) {
            recipients.extend(global);
        }
        
        // Add thread-specific subscribers
        if let Some(thread_id) = thread_id {
            if let Some(thread_subs) = self.thread_subscribers.get(thread_id) {
                recipients.extend(thread_subs);
            }
        }
        
        recipients
    }
}
```

### 2. RPC Handler Implementation

Add to `collab/src/rpc.rs`:

```rust
impl Server {
    pub fn new() -> Arc<Self> {
        let mut server = Server {
            // ... existing fields ...
            agent_subscriptions: Arc::new(RwLock::new(AgentSubscriptions::default())),
        };
        
        // Add agent handlers
        server
            .add_request_handler(subscribe_to_agent_events)
            .add_request_handler(unsubscribe_from_agent_events)
            .add_request_handler(get_agent_threads)
            .add_request_handler(get_agent_thread)
            .add_request_handler(send_agent_command)
            .add_message_handler(handle_agent_event_from_host);
            
        Arc::new(server)
    }
}

// Handler implementations
async fn subscribe_to_agent_events(
    request: proto::SubscribeToAgentEvents,
    response: Response<proto::SubscribeToAgentEvents>,
    session: Session,
) -> Result<()> {
    let user_id = session.user_id;
    let connection_id = session.connection_id;
    
    let mut subscriptions = session.agent_subscriptions.write().await;
    
    if let Some(thread_id) = request.thread_id {
        // Subscribe to specific thread
        subscriptions.subscribe_thread(thread_id, connection_id).await;
    } else {
        // Subscribe to all agent events for this user
        subscriptions.subscribe_global(user_id, connection_id).await;
    }
    
    // Send recent events if requested
    let recent_events = if request.include_history {
        get_recent_agent_events(user_id, request.thread_id.as_deref()).await?
    } else {
        vec![]
    };
    
    response.send(proto::SubscribeToAgentEventsResponse {
        success: true,
        error: None,
        recent_events,
    })?;
    
    Ok(())
}

async fn handle_agent_event_from_host(
    envelope: TypedEnvelope<proto::AgentEvent>,
    session: Session,
) -> Result<()> {
    let event = envelope.payload;
    let user_id = session.user_id;
    
    // Extract thread_id from event
    let thread_id = extract_thread_id(&event);
    
    // Get all recipients
    let subscriptions = session.agent_subscriptions.read().await;
    let recipients = subscriptions.get_recipients(user_id, thread_id.as_deref()).await;
    
    // Broadcast to all recipients
    for connection_id in recipients {
        session.peer.send(
            connection_id,
            proto::AgentEventNotification {
                event: Some(event.clone()),
            },
        ).trace_err();
    }
    
    Ok(())
}
```

### 3. Agent Event Bridge

Create `agent/src/collab_bridge.rs`:

```rust
use agent::{EventBus, Event};
use client::Client;
use gpui::{Context, Model, WeakModel};

pub struct AgentCollabBridge {
    client: Arc<Client>,
    event_bus: Model<EventBus>,
    _subscriptions: Vec<Subscription>,
}

impl AgentCollabBridge {
    pub fn new(
        client: Arc<Client>,
        event_bus: Model<EventBus>,
        cx: &mut Context,
    ) -> Self {
        let mut subscriptions = Vec::new();
        
        // Subscribe to all agent events
        subscriptions.push(cx.subscribe(&event_bus, {
            let client = client.clone();
            move |_, event, _| {
                if let Some(proto_event) = event.to_proto() {
                    client
                        .send(proto_event)
                        .trace_err();
                }
            }
        }));
        
        Self {
            client,
            event_bus,
            _subscriptions: subscriptions,
        }
    }
}

// Event conversion
impl Event {
    pub fn to_proto(&self) -> Option<proto::AgentEvent> {
        let proto_event = match self {
            Event::ThreadCreated { thread } => {
                proto::agent_event::Event::ThreadCreated(proto::ThreadCreated {
                    thread: Some(thread.to_proto()),
                })
            }
            Event::MessageAdded { message } => {
                proto::agent_event::Event::MessageAdded(proto::MessageAdded {
                    message: Some(message.to_proto()),
                })
            }
            Event::MessageStreaming { id, segment, is_final } => {
                proto::agent_event::Event::MessageStreaming(proto::MessageStreaming {
                    message_id: id.clone(),
                    thread_id: self.thread_id().unwrap_or_default(),
                    segment: Some(segment.to_proto()),
                    is_final: *is_final,
                })
            }
            // ... other event types ...
        };
        
        Some(proto::AgentEvent {
            timestamp: Some(SystemTime::now().into()),
            user_id: self.user_id(),
            event: Some(proto_event),
        })
    }
}
```

## Mobile Client Implementation

### 1. Flutter RPC Client

```dart
// lib/services/agent_event_service.dart
import 'package:zed_mobile/proto/agent.pb.dart';
import 'package:zed_mobile/services/rpc_client.dart';

class AgentEventService {
  final RpcClient _rpcClient;
  final _eventController = StreamController<AgentEvent>.broadcast();
  StreamSubscription? _subscription;
  
  Stream<AgentEvent> get events => _eventController.stream;
  
  AgentEventService(this._rpcClient);
  
  Future<void> subscribeToAllEvents() async {
    final request = SubscribeToAgentEvents()
      ..includeHistory = true;
      
    final response = await _rpcClient.request(request);
    
    if (response.success) {
      // Handle recent events
      for (final event in response.recentEvents) {
        _eventController.add(event);
      }
      
      // Subscribe to new events
      _subscription = _rpcClient.notifications
          .where((msg) => msg is AgentEventNotification)
          .map((msg) => (msg as AgentEventNotification).event)
          .listen(_eventController.add);
    }
  }
  
  Future<void> subscribeToThread(String threadId) async {
    final request = SubscribeToAgentEvents()
      ..threadId = threadId
      ..includeHistory = false;
      
    await _rpcClient.request(request);
  }
  
  Future<List<AgentThread>> getThreads() async {
    final request = GetAgentThreads()
      ..limit = 50
      ..includeArchived = false;
      
    final response = await _rpcClient.request(request);
    return response.threads;
  }
  
  Future<void> sendCommand(String threadId, String command) async {
    final request = SendAgentCommand()
      ..threadId = threadId
      ..command = command;
      
    await _rpcClient.request(request);
  }
  
  void dispose() {
    _subscription?.cancel();
    _eventController.close();
  }
}
```

### 2. UI Integration

```dart
// lib/widgets/agent_panel.dart
class AgentPanel extends StatefulWidget {
  @override
  _AgentPanelState createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel> {
  late final AgentEventService _agentService;
  final List<AgentEvent> _events = [];
  
  @override
  void initState() {
    super.initState();
    _agentService = context.read<AgentEventService>();
    _subscribeToEvents();
  }
  
  void _subscribeToEvents() {
    _agentService.subscribeToAllEvents();
    _agentService.events.listen((event) {
      setState(() {
        _events.add(event);
        _handleEvent(event);
      });
    });
  }
  
  void _handleEvent(AgentEvent event) {
    switch (event.whichEvent()) {
      case AgentEvent_Event.threadCreated:
        // Handle new thread
        break;
      case AgentEvent_Event.messageStreaming:
        // Update streaming message
        _updateStreamingMessage(event.messageStreaming);
        break;
      case AgentEvent_Event.toolUseStarted:
        // Show tool use indicator
        break;
      // ... other cases
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildThreadList(),
        Expanded(child: _buildMessageList()),
        _buildCommandInput(),
      ],
    );
  }
}
```

## Implementation Plan

### Phase 1: Protocol & Infrastructure (Week 1-2)
- [ ] Define proto messages
- [ ] Generate Rust and Dart code
- [ ] Add RPC handlers (stub implementations)
- [ ] Set up subscription management

### Phase 2: Server Integration (Week 3-4)
- [ ] Implement agent event bridge
- [ ] Add event routing logic
- [ ] Handle connection lifecycle
- [ ] Add authentication checks

### Phase 3: Desktop Client (Week 5)
- [ ] Connect EventBus to collab bridge
- [ ] Test event flow end-to-end
- [ ] Add error handling and recovery
- [ ] Performance optimization

### Phase 4: Mobile Client (Week 6-7)
- [ ] Implement RPC client
- [ ] Build agent panel UI
- [ ] Add event handling
- [ ] Test on iOS and Android

### Phase 5: Polish & Testing (Week 8)
- [ ] End-to-end testing
- [ ] Performance testing
- [ ] Error scenarios
- [ ] Documentation

## Security Considerations

### Authentication & Authorization

1. **User Isolation**: Users can only subscribe to their own agent events
2. **Thread Access**: Validate thread ownership before sending events
3. **Rate Limiting**: Prevent event spam/DoS

```rust
impl Server {
    async fn validate_agent_access(
        &self,
        user_id: UserId,
        thread_id: &str,
    ) -> Result<bool> {
        // Check if thread belongs to user
        let thread = self.db.get_agent_thread(thread_id).await?;
        Ok(thread.user_id == user_id)
    }
}
```

### Data Privacy

1. **No Persistence**: Agent data is not stored on collab server
2. **Transport Security**: TLS for all connections
3. **Local Mode**: No data leaves the local network

## Performance Considerations

### Event Batching

For high-frequency events (like streaming), batch updates:

```rust
pub struct EventBatcher {
    pending: Vec<proto::AgentEvent>,
    flush_interval: Duration,
    max_batch_size: usize,
}

impl EventBatcher {
    pub async fn add(&mut self, event: proto::AgentEvent) {
        self.pending.push(event);
        
        if self.pending.len() >= self.max_batch_size {
            self.flush().await;
        }
    }
    
    pub async fn flush(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        
        let batch = std::mem::take(&mut self.pending);
        // Send batched events
    }
}
```

### Connection Management

1. **Heartbeat**: Keep connections alive
2. **Reconnection**: Automatic retry with backoff
3. **State Sync**: Recover from disconnections

## Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_subscription_management() {
        let mut subs = AgentSubscriptions::default();
        let user_id = UserId(1);
        let conn_id = ConnectionId(1);
        
        subs.subscribe_global(user_id, conn_id).await;
        let recipients = subs.get_recipients(user_id, None).await;
        assert!(recipients.contains(&conn_id));
    }
    
    #[tokio::test]
    async fn test_event_routing() {
        // Test that events reach the correct subscribers
    }
}
```

### Integration Tests

1. **End-to-End Flow**: Desktop → Server → Mobile
2. **Disconnection Handling**: Events queued during disconnect
3. **Performance**: Measure latency under load
4. **Security**: Verify access control

### Load Testing

```rust
// Simulate multiple clients and high event rates
async fn load_test_agent_events() {
    let clients = 100;
    let events_per_second = 1000;
    
    // Create clients
    let mut handles = vec![];
    for i in 0..clients {
        handles.push(tokio::spawn(simulate_client(i, events_per_second)));
    }
    
    // Measure throughput and latency
}
```

## Monitoring & Observability

### Metrics

1. **Event Latency**: Time from emission to delivery
2. **Subscription Count**: Active subscriptions per user
3. **Error Rate**: Failed event deliveries
4. **Throughput**: Events per second

### Logging

```rust
impl Server {
    async fn broadcast_agent_event(&self, event: proto::AgentEvent) {
        let start = Instant::now();
        let recipients = self.get_recipients(&event).await;
        
        log::debug!(
            "Broadcasting agent event {:?} to {} recipients",
            event.which_event(),
            recipients.len()
        );
        
        // ... broadcast logic ...
        
        metrics::histogram!("agent_event_broadcast_duration")
            .record(start.elapsed());
    }
}
```

## Future Enhancements

1. **Event Persistence**: Optional event history storage
2. **Event Replay**: Replay events for debugging
3. **Multi-Device Sync**: Sync agent state across devices
4. **Collaborative Agents**: Share agent sessions between users
5. **Event Filtering**: Client-side event type filtering
6. **Compression**: Reduce bandwidth for large events
7. **WebTransport**: Lower latency for real-time events

## Conclusion

This integration provides a robust foundation for real-time agent event streaming while leveraging Zed's existing collaboration infrastructure. The implementation is designed to be:

- **Scalable**: Handles multiple subscribers efficiently
- **Secure**: Ensures data isolation between users
- **Performant**: Minimal latency for real-time updates
- **Maintainable**: Follows Zed's architectural patterns

The phased approach allows for incremental development and testing, ensuring a stable integration that enhances the Zed mobile experience.