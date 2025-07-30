# Implementation Plan: PODO Extraction and Zed Core Integration

## Overview

This document outlines the implementation plan for extracting Plain Old Data Objects from Zed's agent implementation and updating Zed itself to use these core types directly. This creates a single source of truth for agent data structures that can be shared between Zed and the mobile app.

## Why This Approach is Better

### Advantages
1. **Single Source of Truth**: One set of data structures used everywhere
2. **No API Extensions Needed**: Avoids complexity of extending Zed's extension API
3. **Better Type Safety**: Direct use of types in Zed ensures consistency
4. **Easier Maintenance**: Changes to data structures automatically propagate
5. **Performance**: No conversion overhead between internal and external types
6. **Cleaner Architecture**: Separation of concerns between data and UI

### Potential Challenges
1. **Refactoring Effort**: Need to update existing agent code
2. **GPUI Dependencies**: Must carefully extract without breaking existing functionality
3. **Backward Compatibility**: Need to ensure existing features continue working

## 1. PODO Extraction - `zed-agent-core` Crate

### 1.1 Create New Crate Structure

```
zed/crates/zed-agent-core/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── types/
│   │   ├── mod.rs
│   │   ├── thread.rs
│   │   ├── message.rs
│   │   ├── context.rs
│   │   ├── tool.rs
│   │   └── event.rs
│   ├── conversion/
│   │   ├── mod.rs
│   │   ├── from_gpui.rs
│   │   └── to_gpui.rs
│   └── serialization/
│       ├── mod.rs
│       └── json.rs
```

### 1.2 Core Types to Extract

```rust
// thread.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
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

// message.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: MessageId,
    pub thread_id: ThreadId,
    pub role: Role,
    pub segments: Vec<MessageSegment>,
    pub timestamp: DateTime<Utc>,
    pub status: MessageStatus,
}

// event.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum AgentEvent {
    ThreadCreated { thread: Thread },
    ThreadUpdated { thread_id: ThreadId, changes: ThreadChanges },
    MessageAdded { thread_id: ThreadId, message: Message },
    MessageStreaming { message_id: MessageId, chunk: String },
    ToolUseStarted { tool_use: ToolUse },
    // ... etc
}
```

### 1.3 Cargo.toml Dependencies

```toml
[package]
name = "zed-agent-core"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1.0", features = ["serde", "v4"] }

[dev-dependencies]
pretty_assertions = "1.4"
```

### 1.4 Conversion Implementation

```rust
// conversion/from_gpui.rs
use crate::types::*;
use agent::{Thread as GpuiThread, Message as GpuiMessage};

impl From<&GpuiThread> for Thread {
    fn from(gpui_thread: &GpuiThread) -> Self {
        Thread {
            id: ThreadId(gpui_thread.id().to_string()),
            title: gpui_thread.summary().map(|s| s.text.clone()),
            messages: gpui_thread.messages()
                .iter()
                .map(Message::from)
                .collect(),
            // ... etc
        }
    }
}
```

## 2. Extend Zed Extension API

### 2.1 Add Agent Capabilities to Extension API

```rust
// In extension_api/wit/since_v0.7.0/agent.wit
interface agent {
    record thread-summary {
        id: string,
        title: option<string>,
        message-count: u32,
        created-at: string,
    }
    
    record agent-event {
        event-type: string,
        data: string, // JSON serialized
    }
    
    /// Subscribe to agent events
    subscribe-to-agent-events: func() -> result<stream<agent-event>>
    
    /// Get all threads
    get-threads: func() -> result<list<thread-summary>>
    
    /// Get thread details
    get-thread: func(thread-id: string) -> result<string> // JSON serialized Thread
}
```

### 2.2 Implement Agent Host Proxy

```rust
// In extension_host/src/agent_proxy.rs
pub trait ExtensionAgentProxy: Send + Sync + 'static {
    fn subscribe_to_events(&self) -> mpsc::Receiver<AgentEvent>;
    fn get_threads(&self) -> Vec<ThreadSummary>;
    fn get_thread(&self, id: &ThreadId) -> Option<Thread>;
}
```

### 2.3 Wire Up to Agent Store

```rust
// In agent/src/extension_bridge.rs
use zed_agent_core::{Thread, AgentEvent};
use extension::ExtensionAgentProxy;

impl ExtensionAgentProxy for AgentExtensionBridge {
    fn subscribe_to_events(&self) -> mpsc::Receiver<AgentEvent> {
        let (tx, rx) = mpsc::channel(100);
        
        // Subscribe to ThreadStore events
        self.thread_store.subscribe(move |event| {
            let core_event = AgentEvent::from(event);
            let _ = tx.try_send(core_event);
        });
        
        rx
    }
}
```

## 3. Create Zed Mobile Bridge Extension

### 3.1 Extension Structure

```
extensions/zed-mobile-bridge/
├── Cargo.toml
├── extension.toml
├── src/
│   ├── lib.rs
│   ├── server.rs
│   └── auth.rs
```

### 3.2 Extension Manifest

```toml
# extension.toml
id = "zed-mobile-bridge"
name = "Zed Mobile Bridge"
version = "0.1.0"
schema_version = 1
authors = ["Fluid Notion Systems"]
description = "Bridge for Zed Mobile app communication"
repository = "https://github.com/fluid-notion-systems/zed-mobile"

[capabilities]
agent = true
network = { ports = [8765] }
```

### 3.3 WebSocket Server Implementation

```rust
// src/server.rs
use zed_extension_api::{self as zed, AgentEvent};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use futures_util::{StreamExt, SinkExt};

struct MobileBridgeServer {
    port: u16,
    auth_token: String,
}

impl MobileBridgeServer {
    async fn start(&self) -> Result<()> {
        let listener = TcpListener::bind(format!("127.0.0.1:{}", self.port)).await?;
        
        while let Ok((stream, _)) = listener.accept().await {
            tokio::spawn(self.handle_connection(stream));
        }
        
        Ok(())
    }
    
    async fn handle_connection(&self, stream: TcpStream) {
        let ws_stream = accept_async(stream).await.unwrap();
        let (mut ws_sender, mut ws_receiver) = ws_stream.split();
        
        // Subscribe to agent events
        let mut event_stream = zed::subscribe_to_agent_events().unwrap();
        
        // Forward events to WebSocket
        tokio::spawn(async move {
            while let Some(event) = event_stream.next().await {
                let json = serde_json::to_string(&event).unwrap();
                ws_sender.send(Message::Text(json)).await.unwrap();
            }
        });
        
        // Handle incoming messages
        while let Some(msg) = ws_receiver.next().await {
            match msg {
                Ok(Message::Text(text)) => {
                    self.handle_request(&text, &mut ws_sender).await;
                }
                _ => break,
            }
        }
    }
}
```

### 3.4 Extension Entry Point

```rust
// src/lib.rs
use zed_extension_api::{self as zed, Extension};

struct ZedMobileBridge {
    server: Option<MobileBridgeServer>,
}

impl Extension for ZedMobileBridge {
    fn new() -> Self {
        Self { server: None }
    }
    
    fn activate(&mut self) {
        // Start WebSocket server
        let server = MobileBridgeServer::new(8765);
        tokio::spawn(server.start());
        self.server = Some(server);
    }
}

zed::register_extension!(ZedMobileBridge);
```

## 4. Implementation Steps

### Phase 1: PODO Extraction (Week 1)
1. [ ] Create `zed-agent-core` crate in `zed/crates/`
2. [ ] Define all PODO types without GPUI dependencies
3. [ ] Implement serde serialization/deserialization
4. [ ] Add builder patterns for complex types
5. [ ] Write comprehensive unit tests

### Phase 2: Update Zed Agent to Use PODOs (Week 2)
1. [ ] Add `zed-agent-core` as dependency to `agent` crate
2. [ ] Replace internal types with PODO types where possible
3. [ ] Implement conversion layer for GPUI-specific parts
4. [ ] Update thread store to emit PODO events
5. [ ] Ensure all tests still pass

### Phase 3: Event System Implementation (Week 3)
1. [ ] Add event bus to `zed-agent-core`
2. [ ] Wire up event emission in agent operations
3. [ ] Create event aggregation for efficient updates
4. [ ] Add event filtering and subscription management
5. [ ] Test event flow end-to-end

### Phase 4: Network Bridge Development (Week 4)
1. [ ] Add WebSocket server to Zed (behind feature flag)
2. [ ] Implement authentication mechanism
3. [ ] Create JSON-RPC or similar protocol
4. [ ] Handle connection lifecycle
5. [ ] Test with Flutter client

## 5. Detailed Implementation Plan

### 5.1 Phase 1 Details: PODO Extraction

#### Create Core Types
```rust
// zed/crates/zed-agent-core/src/types/thread.rs
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Thread {
    pub id: ThreadId,
    pub title: Option<String>,
    pub messages: Vec<Message>,
    pub profile_id: ProfileId,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub status: ThreadStatus,
    pub token_usage: TokenUsage,
}

// Builder pattern for complex construction
impl Thread {
    pub fn builder(id: ThreadId) -> ThreadBuilder {
        ThreadBuilder::new(id)
    }
}
```

#### Integration Points
```rust
// In zed/crates/agent/src/thread.rs
use zed_agent_core::{Thread as CoreThread, Message as CoreMessage};

impl Thread {
    // Convert internal Thread to PODO
    pub fn to_core(&self) -> CoreThread {
        CoreThread {
            id: self.id.clone().into(),
            title: self.summary.as_ref().map(|s| s.text.clone()),
            messages: self.messages.iter().map(|m| m.to_core()).collect(),
            // ... other fields
        }
    }
    
    // Update from PODO (for testing, imports, etc)
    pub fn from_core(core: CoreThread, cx: &mut ModelContext<Self>) -> Self {
        // Implementation
    }
}
```

### 5.2 Phase 2 Details: Zed Integration

#### Update Cargo.toml
```toml
# zed/crates/agent/Cargo.toml
[dependencies]
zed-agent-core = { path = "../zed-agent-core" }
```

#### Refactor Agent to Use PODOs
```rust
// Before: Tightly coupled to GPUI
pub struct Thread {
    id: ThreadId,
    messages: Vec<Entity<Message>>,
    // ... GPUI-specific fields
}

// After: PODO core with GPUI wrapper
pub struct Thread {
    core: zed_agent_core::Thread,
    messages_entities: Vec<Entity<Message>>, // Keep GPUI entities separate
    // ... GPUI-specific fields only
}

impl Thread {
    pub fn core(&self) -> &zed_agent_core::Thread {
        &self.core
    }
    
    pub fn core_mut(&mut self) -> &mut zed_agent_core::Thread {
        &mut self.core
    }
}
```

### 5.3 Phase 3 Details: Event System

#### Event Bus in Core
```rust
// zed/crates/zed-agent-core/src/events/mod.rs
pub struct EventBus {
    subscribers: Arc<RwLock<Vec<Box<dyn EventListener>>>>,
}

impl EventBus {
    pub fn emit(&self, event: AgentEvent) {
        let subscribers = self.subscribers.read();
        for subscriber in subscribers.iter() {
            subscriber.on_event(&event);
        }
    }
}
```

#### Wire Events in Agent
```rust
// In thread operations
impl Thread {
    pub fn add_message(&mut self, message: Message, cx: &mut ModelContext<Self>) {
        // Update core
        self.core.messages.push(message.to_core());
        
        // Emit event
        if let Some(event_bus) = self.event_bus.as_ref() {
            event_bus.emit(AgentEvent::MessageAdded {
                thread_id: self.core.id.clone(),
                message: message.to_core(),
            });
        }
        
        // Continue with GPUI-specific logic
        cx.notify();
    }
}
```

### 5.4 Phase 4 Details: Network Bridge

#### WebSocket Server in Zed
```rust
// zed/crates/zed/src/mobile_bridge.rs
#[cfg(feature = "mobile-bridge")]
pub mod mobile_bridge {
    use zed_agent_core::{EventBus, AgentEvent};
    use tokio::net::TcpListener;
    use tokio_tungstenite::accept_async;
    
    pub struct MobileBridge {
        port: u16,
        event_bus: Arc<EventBus>,
    }
    
    impl MobileBridge {
        pub async fn start(&self) -> Result<()> {
            let addr = format!("127.0.0.1:{}", self.port);
            let listener = TcpListener::bind(&addr).await?;
            
            log::info!("Mobile bridge listening on {}", addr);
            
            while let Ok((stream, _)) = listener.accept().await {
                let event_bus = self.event_bus.clone();
                tokio::spawn(handle_connection(stream, event_bus));
            }
            
            Ok(())
        }
    }
}
```

#### Feature Flag in Cargo.toml
```toml
# zed/Cargo.toml
[features]
mobile-bridge = ["tokio-tungstenite", "zed-agent-core/events"]
```

## 6. Migration Strategy

### 6.1 Gradual Migration
1. Start with read-only data (Thread, Message display)
2. Add write operations (send message, create thread)
3. Implement real-time updates (streaming, events)
4. Full feature parity

### 6.2 Testing During Migration
- Maintain existing test suite
- Add tests for PODO conversions
- Test both old and new code paths
- Performance benchmarks

### 6.3 Rollback Plan
- Keep changes behind feature flags initially
- Maintain backward compatibility
- Document all breaking changes
- Provide migration guides

## 7. Testing Strategy

### Unit Tests
- Test PODO conversions
- Test serialization/deserialization
- Test event transformations

### Integration Tests
- Test WebSocket communication
- Test event streaming
- Test concurrent connections

### End-to-End Tests
- Flutter app ↔ Extension ↔ Zed agent
- Performance under load
- Network failure scenarios

## 8. Security Considerations

### Authentication
- Generate secure token on first connection
- Store in system keychain
- Validate on each WebSocket connection

### Authorization
- Limit exposed operations
- No file system access
- Read-only agent data

### Network Security
- Localhost only by default
- Optional TLS support
- Rate limiting

## 9. Performance Considerations

### Event Batching
- Batch rapid message updates
- Configurable batch size/timeout
- Prioritize user-initiated events

### Memory Management
- Limit cached threads
- Implement message pagination
- Clean up disconnected clients

### Network Efficiency
- Compress large messages
- Delta updates for message streaming
- Binary protocol option (MessagePack)

## 10. Success Criteria

1. **Functionality**: All agent data accessible via extension
2. **Performance**: < 50ms event latency
3. **Reliability**: Auto-reconnection, offline queue
4. **Security**: Secure authentication, no data leaks
5. **Maintainability**: Clean separation, comprehensive tests

## 11. Next Steps

1. **Create `zed-agent-core` crate**: Start with basic types
2. **Prototype Integration**: Update one part of agent to use PODOs
3. **Measure Impact**: Performance and code clarity
4. **Get Team Buy-in**: Present approach to Zed maintainers
5. **Implement Incrementally**: One module at a time

## 12. Example PR Structure

### PR 1: Introduce zed-agent-core
- Add new crate with basic types
- No integration yet
- Comprehensive tests

### PR 2: Use PODOs in Thread
- Update Thread to use core types
- Maintain full compatibility
- Benchmark performance

### PR 3: Add Event System
- Implement event bus
- Wire up basic events
- Behind feature flag

### PR 4: Mobile Bridge
- Add WebSocket server
- Authentication system
- Flutter integration tests

## 13. Conclusion

This approach of having Zed use `zed-agent-core` directly provides the cleanest architecture:
- Single source of truth for data structures
- No complex extension API changes needed
- Better maintainability and type safety
- Clear separation between data and UI concerns

The gradual migration strategy ensures we can deliver value incrementally while maintaining stability.