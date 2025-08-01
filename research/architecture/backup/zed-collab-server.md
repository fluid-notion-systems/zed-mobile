# Zed Collab Server Analysis: Integrating Agent Events

## Overview

The Zed collaboration server (`crates/collab`) is the central hub for real-time collaboration features in Zed. It handles:
- WebSocket connections from Zed clients
- RPC message routing between clients
- Project collaboration (shared editing, LSP, etc.)
- Chat and channels
- Authentication and authorization
- AI/LLM token management

## Current AI/Assistant Infrastructure

### Existing AI Support

The collab server already has some AI-related infrastructure:

1. **LLM Token Management**
   - `get_llm_api_token` RPC handler
   - LLM database for usage tracking
   - Feature flags for AI features (`AGENT_EXTENDED_TRIAL_FEATURE_FLAG`)

2. **Context System** (in `ai.proto`)
   - `Context` - represents an AI conversation context
   - `ContextMessage` - messages within a context
   - `ContextOperation` - CRDT-style operations for syncing
   - RPC handlers for context management:
     - `OpenContext`
     - `CreateContext`
     - `UpdateContext`
     - `SynchronizeContexts`
     - `AdvertiseContexts`

### Key Observations

1. The existing `Context` system appears to be for the older Assistant panel, not the new Agent system
2. No existing infrastructure for Agent threads, events, or real-time updates
3. The collab server uses a handler-based architecture for RPC messages
4. All communication uses Protocol Buffers (protobuf)

## Proposed Agent Integration

### 1. New Proto Definitions

Create a new section in `ai.proto` or a separate `agent.proto`:

```proto
// Agent-specific messages
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

message AgentEvent {
    oneof event {
        ThreadCreated thread_created = 1;
        ThreadUpdated thread_updated = 2;
        MessageAdded message_added = 3;
        MessageStreaming message_streaming = 4;
        ToolUseStarted tool_use_started = 5;
        ToolUseCompleted tool_use_completed = 6;
    }
}

// RPC messages
message SubscribeToAgentEvents {
    optional string thread_id = 1; // Subscribe to specific thread or all
}

message UnsubscribeFromAgentEvents {
    optional string thread_id = 1;
}

message AgentEventNotification {
    AgentEvent event = 1;
}

message GetAgentThreads {}

message GetAgentThreadsResponse {
    repeated AgentThread threads = 1;
}

message GetAgentThread {
    string thread_id = 1;
}

message GetAgentThreadResponse {
    AgentThread thread = 1;
    repeated AgentMessage messages = 2;
}
```

### 2. Collab Server Extensions

#### A. New RPC Handlers

Add to `rpc.rs`:

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

#### B. Agent Event Broadcasting

Create a new module `collab/src/agent.rs`:

```rust
use crate::{rpc::Server, AppState, Result};
use collections::HashMap;
use rpc::proto;
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct AgentSubscriptions {
    // User ID -> Set of connection IDs interested in agent events
    global_subscribers: HashMap<UserId, HashSet<ConnectionId>>,
    // Thread ID -> Set of connection IDs
    thread_subscribers: HashMap<String, HashSet<ConnectionId>>,
}

impl Server {
    pub async fn broadcast_agent_event(
        &self,
        user_id: UserId,
        event: proto::AgentEvent,
    ) -> Result<()> {
        let subscriptions = self.agent_subscriptions.read().await;
        
        // Get all connections that should receive this event
        let mut recipients = HashSet::new();
        
        // Global subscribers for this user
        if let Some(connections) = subscriptions.global_subscribers.get(&user_id) {
            recipients.extend(connections);
        }
        
        // Thread-specific subscribers if applicable
        if let Some(thread_id) = extract_thread_id(&event) {
            if let Some(connections) = subscriptions.thread_subscribers.get(&thread_id) {
                recipients.extend(connections);
            }
        }
        
        // Send to all recipients
        for connection_id in recipients {
            self.peer.send(
                connection_id,
                proto::AgentEventNotification { event: Some(event.clone()) },
            ).trace_err();
        }
        
        Ok(())
    }
}
```

### 3. Integration with Zed Agent

#### A. Agent Store Integration

Modify the Zed agent to emit events through the collab connection:

```rust
// In agent/src/thread.rs or a new agent/src/collab.rs
impl Thread {
    fn emit_event(&mut self, event: AgentEvent, cx: &mut Context) {
        // Convert to proto
        let proto_event = event.to_proto();
        
        // Send through collab client
        if let Some(client) = self.client.upgrade() {
            client.send(proto::AgentEventFromHost {
                event: Some(proto_event),
            }).trace_err();
        }
    }
}
```

#### B. Mobile Client Connection

The mobile app would:

1. Connect to the collab server (existing infrastructure)
2. Send `SubscribeToAgentEvents` message
3. Receive `AgentEventNotification` messages in real-time
4. Query threads/messages as needed with `GetAgentThreads`/`GetAgentThread`

### 4. Implementation Plan

#### Phase 1: Proto Definitions and Basic Infrastructure
1. Add agent proto definitions
2. Generate Rust code from protos
3. Add basic RPC handlers (stubs)

#### Phase 2: Event Broadcasting System
1. Implement subscription management
2. Add event routing logic
3. Handle connection lifecycle (cleanup on disconnect)

#### Phase 3: Zed Integration
1. Hook up agent event emission
2. Add collab client support in agent crate
3. Test end-to-end event flow

#### Phase 4: Mobile Client Support
1. Implement subscription in mobile app
2. Handle incoming events
3. Build UI around real-time updates

### 5. Security Considerations

1. **Authentication**: Only authenticated users can subscribe to their own agent events
2. **Authorization**: Users can only access their own threads/messages
3. **Rate Limiting**: Prevent event spam
4. **Data Privacy**: No agent data is persisted on the collab server (pass-through only)

### 6. Alternative Approach: Direct WebSocket

Instead of going through the collab server, we could:

1. Add a dedicated WebSocket endpoint for agent events
2. Use the existing `zed-agent-core` EventBus
3. Simpler implementation but requires separate connection

Pros:
- Cleaner separation of concerns
- No changes to existing collab protocol
- Easier to implement

Cons:
- Additional connection to manage
- Separate authentication flow
- Not integrated with existing Zed infrastructure

### 7. Recommendation

**Use the collab server approach** because:

1. Leverages existing authentication/connection management
2. Consistent with Zed's architecture
3. Single connection for all features
4. Can reuse existing RPC patterns
5. Better for battery life on mobile (one connection vs multiple)

The implementation should be done incrementally, starting with basic event broadcasting and gradually adding more sophisticated features like thread queries and historical event replay.

### 8. Next Steps

1. Create a proof-of-concept with basic proto definitions
2. Implement a simple event broadcast (e.g., thread created)
3. Test with a mock mobile client
4. Iterate based on performance and usability

This approach provides a solid foundation for real-time agent synchronization between Zed and mobile clients while maintaining consistency with Zed's existing architecture.