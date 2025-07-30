# Zed Agentic Data Structures and Networking Analysis

## Overview

This document analyzes the approach for extracting Plain Old Data Objects (PODO) from Zed's agentic panel implementation and establishing an event-driven network communication layer between Zed and the Flutter mobile app.

## 1. Core Data Structures to Extract

### Thread and Message Types

Based on analysis of `zed/crates/agent/src/thread.rs` and related files:

```rust
// Core PODOs to extract (without GPUI dependencies)
pub struct ThreadId(String);
pub struct MessageId(String);
pub struct PromptId(String);

pub struct Thread {
    pub id: ThreadId,
    pub title: Option<String>,
    pub messages: Vec<Message>,
    pub profile_id: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub status: ThreadStatus,
    pub token_usage: TokenUsage,
}

pub struct Message {
    pub id: MessageId,
    pub thread_id: ThreadId,
    pub role: Role,
    pub segments: Vec<MessageSegment>,
    pub timestamp: DateTime<Utc>,
    pub status: MessageStatus,
}

pub enum MessageSegment {
    Text(String),
    ToolUse(ToolUse),
    ToolResult(ToolResult),
    Context(ContextReference),
}

pub struct ToolUse {
    pub id: String,
    pub name: String,
    pub input: serde_json::Value,
    pub status: ToolUseStatus,
    pub metadata: ToolUseMetadata,
}

pub enum ThreadStatus {
    Idle,
    Running,
    Error(String),
}

pub struct TokenUsage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}
```

### Context and Tool Types

```rust
pub struct AgentContext {
    pub id: String,
    pub name: String,
    pub kind: ContextKind,
    pub content: String,
    pub metadata: HashMap<String, serde_json::Value>,
}

pub enum ContextKind {
    File { path: String, language: Option<String> },
    Directory { path: String },
    Symbol { name: String, kind: String },
    Thread { thread_id: ThreadId },
    Url { url: String },
}
```

## 2. Event-Driven Architecture

### Event Types

```rust
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(tag = "type", content = "data")]
pub enum AgentEvent {
    // Thread Events
    ThreadCreated { thread: Thread },
    ThreadUpdated { thread_id: ThreadId, changes: ThreadChanges },
    ThreadDeleted { thread_id: ThreadId },
    
    // Message Events
    MessageAdded { thread_id: ThreadId, message: Message },
    MessageUpdated { message_id: MessageId, segments: Vec<MessageSegment> },
    MessageStreaming { message_id: MessageId, chunk: String },
    MessageCompleted { message_id: MessageId },
    
    // Tool Events
    ToolUseStarted { tool_use: ToolUse },
    ToolUseUpdated { tool_id: String, status: ToolUseStatus },
    ToolUseCompleted { tool_id: String, result: ToolResult },
    
    // Status Events
    ThreadStatusChanged { thread_id: ThreadId, status: ThreadStatus },
    TokenUsageUpdated { thread_id: ThreadId, usage: TokenUsage },
    ErrorOccurred { thread_id: Option<ThreadId>, error: ErrorInfo },
}
```

### Event Bus Design

```rust
// In the new zed-agent-core crate
pub trait EventListener: Send + Sync {
    fn on_event(&self, event: &AgentEvent);
}

pub struct EventBus {
    listeners: Arc<RwLock<Vec<Box<dyn EventListener>>>>,
}

impl EventBus {
    pub fn subscribe(&self, listener: Box<dyn EventListener>) -> ListenerId;
    pub fn unsubscribe(&self, id: ListenerId);
    pub fn emit(&self, event: AgentEvent);
}
```

## 3. Current Zed Networking Stack

### Existing Infrastructure

1. **Tokio Runtime**: Zed uses tokio for async runtime
   - Already integrated throughout the codebase
   - Handles async I/O, timers, and task scheduling

2. **HTTP Client**: `http_client` crate
   - Based on isahc/curl
   - Used for LLM API calls

3. **WebRTC**: For collaboration features
   - Peer-to-peer communication
   - Already has signaling infrastructure

4. **Protocol Buffers**: For serialization
   - Used in collaboration features
   - Efficient binary protocol

### Relevant Crates

- `rpc`: Zed's RPC implementation
- `proto`: Protocol buffer definitions
- `client`: Client connection management
- `collab`: Collaboration infrastructure

## 4. Network Architecture Options

### Option 1: WebSocket Server (Recommended)

**Pros:**
- Real-time bidirectional communication
- Works well with Flutter
- Can reuse existing tokio infrastructure
- Simple event streaming

**Implementation:**
```rust
// In Zed extension
use tokio_tungstenite::{accept_async, WebSocketStream};

pub struct MobileAgentServer {
    event_bus: Arc<EventBus>,
    connections: Arc<RwLock<HashMap<ConnectionId, WebSocketStream>>>,
}

impl MobileAgentServer {
    pub async fn start(&self, port: u16) -> Result<()> {
        let listener = TcpListener::bind(format!("127.0.0.1:{}", port)).await?;
        
        while let Ok((stream, _)) = listener.accept().await {
            let ws_stream = accept_async(stream).await?;
            self.handle_connection(ws_stream).await;
        }
    }
}
```

### Option 2: gRPC Server

**Pros:**
- Type-safe API
- Efficient binary protocol
- Streaming support
- Good Flutter support

**Cons:**
- More complex setup
- Requires protobuf definitions

### Option 3: Local HTTP Server with SSE

**Pros:**
- Simple implementation
- Good for one-way event streaming
- Easy to debug

**Cons:**
- Requires polling for bidirectional communication
- Less efficient than WebSockets

## 5. Flutter Integration

### Recommended Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  # WebSocket client
  web_socket_channel: ^2.4.0
  
  # State management (event-driven)
  riverpod: ^2.5.0
  
  # JSON serialization
  json_annotation: ^4.8.1
  freezed_annotation: ^2.4.1
  
  # Networking utilities
  dio: ^5.4.0
  
  # Event bus
  event_bus: ^2.0.0
  
  # Secure storage for auth
  flutter_secure_storage: ^9.0.0

dev_dependencies:
  build_runner: ^2.4.0
  json_serializable: ^6.7.0
  freezed: ^2.4.0
```

### Flutter Event Architecture

```dart
// Event stream provider
final agentEventStreamProvider = StreamProvider<AgentEvent>((ref) {
  final webSocket = ref.watch(webSocketProvider);
  return webSocket.stream
      .map((data) => AgentEvent.fromJson(jsonDecode(data)));
});

// State notifiers for different data
class ThreadListNotifier extends StateNotifier<List<Thread>> {
  ThreadListNotifier() : super([]);
  
  void handleEvent(AgentEvent event) {
    switch (event) {
      case ThreadCreated(:final thread):
        state = [...state, thread];
      case ThreadUpdated(:final threadId, :final changes):
        state = state.map((t) => 
          t.id == threadId ? t.copyWith(changes) : t
        ).toList();
      // ... other events
    }
  }
}
```

## 6. Implementation Strategy

### Phase 1: Core Data Extraction
1. Create `zed-agent-core` crate with PODO types
2. Implement serialization (serde)
3. Add conversion from GPUI types to PODOs

### Phase 2: Event System
1. Implement EventBus in Zed
2. Add event emission points in agent code
3. Create event aggregation layer

### Phase 3: Network Server
1. Implement WebSocket server in Zed extension
2. Add authentication/security
3. Handle connection lifecycle

### Phase 4: Flutter Client
1. WebSocket client implementation
2. Event stream handling
3. State management integration
4. Offline support

## 7. Security Considerations

### Authentication
- Token-based auth (JWT or similar)
- Secure token storage on mobile
- Token refresh mechanism

### Encryption
- TLS for WebSocket connections
- Consider end-to-end encryption for sensitive data

### Access Control
- Limit exposed functionality
- Validate all inputs
- Rate limiting

## 8. Example Message Flow

```
Flutter App          WebSocket          Zed Extension         Agent Core
    |                    |                     |                   |
    |--Connect---------->|                     |                   |
    |                    |--Authenticate------>|                   |
    |<---Connected-------|                     |                   |
    |                    |                     |                   |
    |--Subscribe-------->|--Register Listener->|--Hook Events----->|
    |                    |                     |                   |
    |                    |                     |<--Thread Created--|
    |                    |<--Event: ThreadCreated                  |
    |<--Thread Created---|                     |                   |
    |                    |                     |                   |
    |--Send Message----->|--Process----------->|--Add Message----->|
    |                    |                     |<--Message Added---|
    |<--Message Added----|<--Event: MessageAdded                   |
```

## 9. Performance Considerations

### Event Throttling
- Batch rapid events (e.g., streaming text)
- Implement debouncing for UI updates
- Consider event priority queues

### Data Synchronization
- Incremental updates vs full sync
- Conflict resolution strategy
- Offline queue management

### Memory Management
- Limit cached threads/messages
- Implement pagination
- Clean up old event listeners

## 10. Next Steps

1. **Prototype Core Types**: Create minimal `zed-agent-core` crate
2. **Test Serialization**: Ensure clean JSON output
3. **Implement Event Bus**: Start with in-memory implementation
4. **WebSocket POC**: Basic server in Zed, client in Flutter
5. **Iterate**: Based on performance and usability testing

## Conclusion

The recommended approach is to:
1. Extract PODO types into a separate crate
2. Use WebSocket for real-time communication
3. Implement event-driven architecture on both sides
4. Use Riverpod for Flutter state management
5. Focus on incremental, testable implementations

This architecture provides a clean separation between Zed's GPUI-dependent code and the mobile-friendly data layer while maintaining real-time synchronization capabilities.