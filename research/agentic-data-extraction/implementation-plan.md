# Implementation Plan: PODO Extraction and Zed Extension

## Overview

This document outlines the implementation plan for extracting Plain Old Data Objects from Zed's agent implementation and creating a Zed extension that exposes agent data to the mobile app.

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
1. [ ] Create `zed-agent-core` crate
2. [ ] Define all PODO types
3. [ ] Implement serialization
4. [ ] Add conversion from GPUI types
5. [ ] Write comprehensive tests

### Phase 2: Zed API Extension (Week 2)
1. [ ] Add agent interface to WIT
2. [ ] Implement agent proxy trait
3. [ ] Create extension bridge in agent crate
4. [ ] Wire up event subscriptions
5. [ ] Test API functionality

### Phase 3: Extension Development (Week 3)
1. [ ] Create extension project
2. [ ] Implement WebSocket server
3. [ ] Add authentication
4. [ ] Handle all agent operations
5. [ ] Test with mock client

### Phase 4: Integration Testing (Week 4)
1. [ ] Test with Flutter app
2. [ ] Performance optimization
3. [ ] Security hardening
4. [ ] Documentation
5. [ ] Release preparation

## 5. Alternative Approaches

### 5.1 If Extension API Changes Are Not Possible

If we cannot modify Zed's extension API, we could:

1. **Fork Zed**: Maintain a fork with agent API exposed
2. **Plugin System**: Create a plugin system in the agent module
3. **IPC Bridge**: Use local IPC (Unix sockets, named pipes)
4. **File-based Communication**: Write events to local files

### 5.2 Direct Integration Option

Alternatively, add the WebSocket server directly to Zed:

```rust
// In zed/src/mobile_bridge.rs
#[cfg(feature = "mobile-bridge")]
mod mobile_bridge {
    pub fn start_server(agent: Arc<Agent>) {
        // WebSocket server implementation
    }
}
```

## 6. Testing Strategy

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

## 7. Security Considerations

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

## 8. Performance Considerations

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

## 9. Success Criteria

1. **Functionality**: All agent data accessible via extension
2. **Performance**: < 50ms event latency
3. **Reliability**: Auto-reconnection, offline queue
4. **Security**: Secure authentication, no data leaks
5. **Maintainability**: Clean separation, comprehensive tests

## 10. Next Steps

1. **Validate Approach**: Discuss with Zed team
2. **Prototype PODO**: Create minimal extraction
3. **Test Extension API**: Verify capabilities
4. **Build MVP**: Basic event streaming
5. **Iterate**: Based on testing feedback