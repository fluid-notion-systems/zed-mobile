# Zed Extension API Analysis

## Overview

This document analyzes Zed's extension API capabilities and architecture, specifically focusing on how to build an extension that can expose the agent panel data and provide real-time updates to a mobile application.

## Current Extension System

### Extension Architecture

Zed extensions are WebAssembly (WASM) modules that run in a sandboxed environment. They communicate with the host editor through a defined API surface.

```toml
# extension.toml structure
id = "zed-mobile-bridge"
name = "Zed Mobile Bridge"
version = "0.1.0"
schema_version = 1
authors = ["Your Name <email@example.com>"]
description = "Bridge extension for Zed Mobile app"
repository = "https://github.com/yourusername/zed-mobile"
```

### Core Extension APIs

#### 1. Language Server Protocol (LSP)
- Extensions can provide language servers
- Not directly applicable for our use case
- Could potentially hijack for custom protocol

#### 2. Themes and UI
- Extensions can provide themes
- Limited UI customization capabilities
- Cannot directly access panel contents

#### 3. Commands and Actions
- Register custom commands
- Bind to keyboard shortcuts
- Execute editor actions

### Current Limitations

1. **No Direct Panel Access**: Extensions cannot directly read panel contents
2. **Limited IPC**: No built-in mechanism for external communication
3. **Sandboxed Environment**: WASM restrictions on networking
4. **Event System**: Limited access to editor events

## Proposed Solutions

### Solution 1: Core Zed Modification

Since direct extension API access to panels is limited, we need to modify Zed core:

```rust
// crates/agent_ui/src/agent_panel.rs modification
impl AgentPanel {
    pub fn expose_for_mobile(&self, cx: &mut Context<Self>) -> MobileApiHandle {
        let (tx, rx) = mpsc::channel(1024);

        // Subscribe to panel updates
        cx.observe(&self.active_thread, move |panel, _, cx| {
            if let Some(thread) = panel.active_thread.as_ref() {
                let entries = thread.read(cx).entries().to_vec();
                tx.try_send(PanelUpdate::Entries(entries)).ok();
            }
        }).detach();

        MobileApiHandle { receiver: rx }
    }
}
```

### Solution 2: Extension with Native Component

Create a hybrid extension with a native sidecar process:

```rust
// Extension manifest
[capabilities]
native_binary = true
network_access = true

// Native component that runs alongside WASM
pub struct MobileBridge {
    websocket_server: WebSocketServer,
    zed_connection: ZedConnection,
}

impl MobileBridge {
    pub async fn start(&mut self) -> Result<()> {
        // Start WebSocket server for mobile connections
        self.websocket_server.listen("0.0.0.0:8765").await?;

        // Connect to Zed's internal APIs
        self.zed_connection.subscribe_to_agent_panel().await?;

        // Forward events
        while let Some(event) = self.zed_connection.next_event().await {
            self.websocket_server.broadcast(event).await?;
        }

        Ok(())
    }
}
```

### Solution 3: Language Server Protocol Abuse

Use LSP as a communication channel:

```rust
// Fake language server that actually bridges mobile communication
struct MobileBridgeLanguageServer {
    mobile_connections: Arc<Mutex<Vec<WebSocketConnection>>>,
}

impl LanguageServer for MobileBridgeLanguageServer {
    // Intercept custom requests
    async fn custom_request(&self, method: &str, params: Value) -> Result<Value> {
        match method {
            "zedMobile/subscribe" => self.handle_mobile_subscribe(params).await,
            "zedMobile/sendCommand" => self.handle_mobile_command(params).await,
            _ => Err(Error::MethodNotFound),
        }
    }
}
```

## Accessing Agent Panel Data

### Internal Data Structures

Based on the codebase analysis:

```rust
// Key structures we need to access
pub struct AgentThread {
    entries: Vec<AgentThreadEntry>,
    // ... other fields
}

pub enum AgentThreadEntry {
    UserMessage(UserMessage),
    AssistantMessage(AssistantMessage),
    ToolCall(ToolCall),
}

pub struct ToolCall {
    id: String,
    name: String,
    status: ToolCallStatus,
    diffs: Vec<Diff>,
    locations: Vec<ToolCallLocation>,
}
```

### Event Stream Architecture

```rust
// Proposed event streaming API
pub trait AgentPanelObserver {
    fn on_entry_added(&mut self, entry: &AgentThreadEntry);
    fn on_tool_call_updated(&mut self, id: &str, status: ToolCallStatus);
    fn on_session_started(&mut self, session_id: SessionId);
    fn on_session_ended(&mut self, session_id: SessionId);
}

// Extension registration
impl Extension for ZedMobileBridge {
    fn activate(&mut self, cx: &mut ExtensionContext) {
        cx.register_agent_panel_observer(Box::new(self));
    }
}
```

## Communication Protocol Design

### WebSocket Messages

```typescript
// TypeScript definitions for protocol
interface MobileProtocol {
    // Server -> Mobile
    serverMessages: {
        agentOutput: {
            type: "agent_output";
            sessionId: string;
            entry: AgentThreadEntry;
            timestamp: number;
        };

        toolCallUpdate: {
            type: "tool_call_update";
            sessionId: string;
            toolCallId: string;
            status: ToolCallStatus;
            diffs?: Diff[];
        };

        sessionUpdate: {
            type: "session_update";
            sessionId: string;
            status: "started" | "ended" | "active";
        };
    };

    // Mobile -> Server
    clientMessages: {
        subscribe: {
            type: "subscribe";
            sessionId?: string; // Optional: specific session
        };

        sendMessage: {
            type: "send_message";
            sessionId: string;
            content: string;
        };

        executeCommand: {
            type: "execute_command";
            command: string;
            args: any[];
        };
    };
}
```

### Binary Protocol with Protocol Buffers

```protobuf
syntax = "proto3";

package zedmobile.agent;

message StreamRequest {
    oneof request {
        Subscribe subscribe = 1;
        SendMessage send_message = 2;
        ExecuteCommand execute_command = 3;
    }
}

message StreamResponse {
    oneof response {
        AgentEntry agent_entry = 1;
        ToolCallUpdate tool_call_update = 2;
        SessionStatus session_status = 3;
        Error error = 4;
    }
}

message AgentEntry {
    string session_id = 1;
    int64 timestamp = 2;

    oneof content {
        UserMessage user = 3;
        AssistantMessage assistant = 4;
        ToolCall tool_call = 5;
    }
}
```

## Extension Implementation Strategy

### Phase 1: Proof of Concept
1. Fork Zed to add mobile API endpoints
2. Create simple WebSocket server in Rust
3. Expose agent panel events through custom API

### Phase 2: Official Extension API
1. Propose extension API additions to Zed team
2. Implement proper event subscription system
3. Add sandboxed networking capabilities

### Phase 3: Production Ready
1. Authentication and authorization
2. Encrypted communication
3. Rate limiting and resource management

## Security Considerations

### Authentication Methods
```rust
// API key authentication
pub struct ApiKeyAuth {
    key: String,
    permissions: Vec<Permission>,
}

// OAuth 2.0 flow
pub struct OAuthConfig {
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    scopes: Vec<String>,
}

// Device certificate
pub struct DeviceCertAuth {
    cert_path: PathBuf,
    key_path: PathBuf,
    ca_bundle: PathBuf,
}
```

### Permission Model
```rust
pub enum Permission {
    ReadAgentPanel,
    WriteAgentPanel,
    ExecuteCommands,
    AccessWorkspace,
    ModifyFiles,
}

pub struct MobileSession {
    id: SessionId,
    permissions: HashSet<Permission>,
    rate_limits: RateLimits,
}
```

## Performance Optimization

### Message Batching
```rust
pub struct MessageBatcher {
    buffer: VecDeque<AgentMessage>,
    max_batch_size: usize,
    flush_interval: Duration,
    compression: CompressionType,
}

impl MessageBatcher {
    pub async fn flush(&mut self) -> Result<Batch> {
        let messages = self.buffer.drain(..).collect();
        let batch = Batch::new(messages);

        match self.compression {
            CompressionType::Gzip => batch.compress_gzip(),
            CompressionType::Zstd => batch.compress_zstd(),
            CompressionType::None => Ok(batch),
        }
    }
}
```

### Caching Strategy
```rust
pub struct AgentPanelCache {
    entries: LruCache<EntryId, AgentThreadEntry>,
    sessions: HashMap<SessionId, SessionCache>,
    max_memory: usize,
}
```

## Integration with Existing Zed Systems

### Event Bus Integration
```rust
// Hook into Zed's event system
impl EventHandler for MobileExtension {
    fn handle_event(&mut self, event: &EditorEvent, cx: &mut Context) {
        match event {
            EditorEvent::AgentPanelUpdated(update) => {
                self.broadcast_to_mobile_clients(update);
            }
            EditorEvent::WorkspaceChanged(_) => {
                self.update_context();
            }
            _ => {}
        }
    }
}
```

### Workspace Context
```rust
pub struct MobileContext {
    active_workspace: WorkspaceId,
    active_buffer: Option<BufferId>,
    agent_location: Option<AgentLocation>,
    open_panels: Vec<PanelId>,
}
```

## Future Extension API Proposals

### Proposed API Additions
1. **Panel Access API**: Direct read access to panel contents
2. **Event Subscription**: Subscribe to specific editor events
3. **IPC Mechanism**: Communication with external processes
4. **Network Permissions**: Allow controlled network access

### Example API Usage
```rust
// Ideal future extension API
impl Extension for ZedMobile {
    fn capabilities(&self) -> Capabilities {
        Capabilities {
            panel_access: vec![PanelType::Agent, PanelType::Terminal],
            network: NetworkCapability::Server(8765),
            ipc: true,
        }
    }

    fn on_panel_update(&mut self, panel: PanelType, update: PanelUpdate) {
        match panel {
            PanelType::Agent => self.handle_agent_update(update),
            _ => {}
        }
    }
}
```

## Conclusion

Currently, Zed's extension API lacks direct access to panel contents and external communication capabilities. The most viable approach for Zed Mobile is:

1. **Short-term**: Fork Zed and add custom mobile bridge functionality
2. **Medium-term**: Collaborate with Zed team to add necessary extension APIs
3. **Long-term**: Build a proper extension once APIs are available

The architecture should be designed to easily transition from a forked solution to an official extension once the APIs become available.
