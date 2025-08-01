# Zed Proto/Collab Integration Research

## Overview
Research into how Zed handles proto message integration and event routing between local components and the collab server. This investigation focuses on understanding the patterns to implement agent event routing.

## Key Discoveries

### Event Flow Pattern
- No central event bus exists in Zed for GPUI events
- Components directly subscribe to entities they care about
- Events are handled locally and selectively forwarded as proto messages
- Uses direct subscription model rather than global event broadcasting

### Implementation Patterns
- Local systems (like BufferStore) subscribe to entity events
- Event handlers process events and determine what to send
- Client requests send proto messages to server using `client.request()`
- Subscriptions are managed at the entity level
- Server uses `add_request_handler` and `add_message_handler` for registration

### Key Components
1. **Local Event Subscription**
   - Components subscribe directly to entities
   - Subscription handles are stored
   - Events are processed locally first

2. **Proto Message Handling**
   - Events are converted to proto messages when needed
   - Uses client.request() for server communication
   - Follows request/response pattern for server interaction

3. **Server Communication**
   - Direct client-to-server communication
   - No intermediate event bus or broker
   - Clean separation between local and remote events

## Validated Implementation Approach

### ✅ Architecture Validation
The approach is well-aligned with Zed's architecture:
- Proto definitions are complete (`crates/proto/proto/agent.proto`)
- Proto conversions are partially implemented (`crates/agent/src/proto/mod.rs`)
- Collab server has established patterns for event handling
- Agent messages are registered in the proto system

### 1. **ThreadStore Event Subscription**

Add subscription logic when threads are created:

```rust
// In thread_store.rs
pub fn create_thread(&mut self, cx: &mut Context<Self>) -> Entity<Thread> {
    let thread = cx.new(|cx| {
        Thread::new(
            self.project.clone(),
            self.tools.clone(),
            self.prompt_builder.clone(),
            self.project_context.clone(),
            cx,
        )
    });
    
    // Add event subscription for collab forwarding
    if let Some(client) = self.client.as_ref() {
        self.thread_subscriptions.insert(
            thread.id(),
            cx.subscribe(&thread, move |store, thread, event, cx| {
                store.handle_thread_event(thread, event, cx);
            })
        );
    }
    
    thread
}

// New method to handle thread events
impl ThreadStore {
    fn handle_thread_event(
        &mut self,
        thread: Entity<Thread>,
        event: &ThreadEvent,
        cx: &mut Context<Self>
    ) {
        // Convert event to proto and send to server
        if let Some(client) = self.client.as_ref() {
            let thread_id = thread.read(cx).id();
            let proto_event = event.into(); // Uses proto conversion
            
            // Send event notification to server
            cx.background_executor().spawn(async move {
                client
                    .send(proto::AgentEventNotification {
                        event: Some(proto::AgentEvent {
                            event_id: Uuid::new_v4().to_string(),
                            timestamp: Some(Timestamp::now()),
                            user_id: client.user_id().to_string(),
                            thread_id: Some(thread_id.into()),
                            event: Some(proto_event),
                        }),
                    })
                    .log_err();
            }).detach();
        }
    }
}
```

### 2. **Collab Server Handler Registration**

Add agent-specific handlers to the RPC server:

```rust
// In crates/collab/src/rpc.rs
server
    // ... existing handlers ...
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
    .add_message_handler(broadcast_agent_event);
```

### 3. **Proto Conversion Completion**

Key conversions needed in `crates/agent/src/proto/mod.rs`:
- Complete all `ThreadEvent` variant conversions
- Implement `LoadedContext` and `ContextItem` conversions
- Add tool-related conversions (`PendingToolUse`, `ToolUseSegment`)
- Implement checkpoint and restore conversions
- Add completion and retry state conversions

### 4. **Direct Event Routing**

Since there's no event bridge, implement direct routing in ThreadStore:

```rust
// ThreadStore maintains client connection
pub struct ThreadStore {
    project: Entity<Project>,
    tools: Entity<ToolWorkingSet>,
    prompt_store: Option<Entity<PromptStore>>,
    prompt_builder: Arc<PromptBuilder>,
    client: Option<Arc<Client>>, // Add client reference
    thread_subscriptions: HashMap<ThreadId, Subscription>,
    // ... other fields
}

// Initialize with client
impl ThreadStore {
    pub fn new_with_client(
        // ... existing params
        client: Arc<Client>,
        cx: &mut Context<Self>
    ) -> Self {
        Self {
            // ... existing fields
            client: Some(client),
            thread_subscriptions: HashMap::new(),
        }
    }
}
```

## Implementation Details

### Event Routing Flow
1. Thread emits `ThreadEvent` (GPUI event)
2. ThreadStore subscription catches the event
3. Event is converted to proto message via `Into` trait
4. Client sends `AgentEventNotification` to server
5. Server broadcasts to subscribed clients
6. Mobile client receives and processes event

### Security Considerations
- **Authentication**: Validate thread ownership before sending events
- **Authorization**: Users can only subscribe to their own threads
- **Rate Limiting**: Consider throttling high-frequency events

### Performance Optimizations
- **Event Filtering**: Not all events need forwarding (e.g., UI-only events)
- **Batching**: Group multiple `StreamedAssistantText` events
- **Selective Subscription**: Allow subscribing to specific event types

## Handler Implementation Examples

### Subscribe to Agent Events Handler
```rust
async fn subscribe_to_agent_events(
    request: proto::SubscribeToAgentEvents,
    response: Response<proto::SubscribeToAgentEvents>,
    session: Session,
) -> Result<()> {
    let user_id = session.user_id();
    
    // Validate thread ownership if specific thread requested
    if let Some(thread_id) = request.thread_id {
        validate_thread_ownership(user_id, thread_id)?;
    }
    
    // Register subscription
    session.agent_subscriptions.insert(
        thread_id.unwrap_or_default(),
        AgentSubscription {
            since_timestamp: request.since_timestamp,
            last_event_id: request.last_event_id,
        }
    );
    
    // Send recent events if requested
    let recent_events = if request.since_timestamp.is_some() {
        get_recent_events(user_id, request.thread_id, request.since_timestamp)?
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
```

## Next Steps

1. **Complete Proto Conversions**
   - Finish all type conversions in `agent/src/proto/mod.rs`
   - Add tests for proto serialization/deserialization

2. **Implement Collab Handlers**
   - Create handler functions for each agent RPC
   - Add thread ownership validation
   - Implement event broadcasting logic

3. **Wire Up Direct Event Routing**
   - Add client reference to ThreadStore
   - Implement event forwarding logic
   - Handle connection lifecycle

4. **Testing**
   - Unit tests for proto conversions
   - Integration tests for event flow
   - End-to-end mobile client testing

## Code Locations

- **Proto Definitions**: `crates/proto/proto/agent.proto`
- **Proto Conversions**: `crates/agent/src/proto/mod.rs`
- **Thread Store**: `crates/agent/src/thread_store.rs`
- **Thread Implementation**: `crates/agent/src/thread.rs`
- **Collab Server**: `crates/collab/src/rpc.rs`
- **Proto Registration**: `crates/proto/src/proto.rs`

## Summary

The implementation approach is validated and ready for execution. The key insight is that Zed's existing patterns for buffer and project event handling can be directly applied to agent events. Without a separate event bridge, the ThreadStore will handle event routing directly through the client connection, following the same patterns used elsewhere in Zed.