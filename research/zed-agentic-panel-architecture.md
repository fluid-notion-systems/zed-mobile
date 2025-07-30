# Zed Agentic Panel Architecture Research

## Overview

This document provides a comprehensive analysis of Zed's agentic panel implementation, including its architecture, data structures, and integration points. This research is crucial for building a mobile companion app that can monitor and interact with the agent panel.

## Core Architecture

### Component Hierarchy

```
AgentPanel (Main Panel)
├── ActiveView (View State Management)
│   ├── Thread (Active AI conversation)
│   ├── ExternalAgentThread (External agent integration)
│   ├── TextThread (Prompt editor)
│   ├── History (Thread history)
│   └── Configuration (Settings)
├── ThreadStore (Data Management)
├── MessageEditor (User Input)
└── UI Components
    ├── NavigationMenu
    ├── OptionsMenu
    └── ModelSelector
```

### Key Modules

1. **agent_panel.rs** - Main panel implementation
2. **active_thread.rs** - Active conversation management
3. **acp_thread.rs** - Agent Client Protocol implementation
4. **thread_store.rs** - Thread persistence and management
5. **message_editor.rs** - User input handling

## Data Structures

### Thread Hierarchy

```rust
// Core thread structure
pub struct Thread {
    id: ThreadId,
    updated_at: DateTime<Utc>,
    summary: ThreadSummary,
    messages: Vec<Message>,
    completion_mode: CompletionMode,
    model: ConfiguredModel,
    token_usage: TokenUsage,
    project_state: Option<ProjectState>,
}

// Thread identification
pub struct ThreadId(Arc<str>);

// Thread metadata for storage
pub struct SerializedThreadMetadata {
    pub id: ThreadId,
    pub summary: SharedString,
    pub updated_at: DateTime<Utc>,
}
```

### Message Structure

```rust
// Individual message in a thread
pub struct Message {
    pub id: MessageId,
    pub role: Role,  // User, Assistant, System
    pub segments: Vec<MessageSegment>,
    pub loaded_context: LoadedContext,
    pub creases: Vec<MessageCrease>,  // Collapsible sections
    pub is_hidden: bool,
    pub ui_only: bool,
}

// Message identification
pub struct MessageId(pub(crate) usize);

// Message content segments
pub enum MessageSegment {
    Text(String),
    Context {
        context_id: ContextId,
        start: usize,
        end: usize,
    },
    ToolUse(ToolUse),
}
```

### Agent Thread Entries (ACP)

```rust
// Agent Client Protocol entries
pub enum AgentThreadEntry {
    UserMessage(UserMessage),
    AssistantMessage(AssistantMessage),
    ToolCall(ToolCall),
}

// Tool call representation
pub struct ToolCall {
    id: String,
    name: String,
    status: ToolCallStatus,
    diffs: Vec<Diff>,
    locations: Vec<ToolCallLocation>,
}

// Tool call status
pub enum ToolCallStatus {
    WaitingForConfirmation,
    Allowed,
    Rejected,
    Canceled,
}
```

### Context Management

```rust
// Context handles for different types
pub enum AgentContextHandle {
    Thread(ThreadContextHandle),
    TextThread(TextThreadContextHandle),
    File(FileContextHandle),
    Directory(DirectoryContextHandle),
    // ... other context types
}

// Thread context reference
pub struct ThreadContextHandle {
    pub thread: Entity<Thread>,
    pub context_id: ContextId,
}
```

## Message Flow

### 1. User Input Flow
```
User Input (MessageEditor)
    ↓
Parse Slash Commands & Mentions
    ↓
Build Message with Context
    ↓
Send to Thread
    ↓
Update UI & Persist
```

### 2. Assistant Response Flow
```
Receive from Language Model
    ↓
Parse Response (Text/ToolCalls)
    ↓
Create AssistantMessage
    ↓
Process Tool Calls
    ↓
Update Thread & UI
```

### 3. Tool Call Flow
```
Tool Call Detected
    ↓
Create ToolCall Entry
    ↓
Wait for User Confirmation (if required)
    ↓
Execute Tool
    ↓
Apply Diffs/Changes
    ↓
Update Status
```

## State Management

### Active View States

The AgentPanel maintains different view states:

```rust
enum ActiveView {
    Thread {
        thread: Entity<ActiveThread>,
        change_title_editor: Entity<Editor>,
        message_editor: Entity<MessageEditor>,
        _subscriptions: Vec<gpui::Subscription>,
    },
    ExternalAgentThread {
        thread_view: Entity<AcpThreadView>,
    },
    TextThread {
        context_editor: Entity<TextThreadEditor>,
        title_editor: Entity<Editor>,
        buffer_search_bar: Entity<BufferSearchBar>,
        _subscriptions: Vec<gpui::Subscription>,
    },
    History,
    Configuration,
}
```

### Thread Store

The ThreadStore manages all threads and provides:
- Thread creation and deletion
- Persistence to disk
- Model configuration
- Tool management
- Context server integration

```rust
pub struct ThreadStore {
    project: Entity<Project>,
    tools: Entity<ToolWorkingSet>,
    prompt_builder: Arc<PromptBuilder>,
    prompt_store: Option<Entity<PromptStore>>,
    threads: Vec<SerializedThreadMetadata>,
    project_context: SharedProjectContext,
}
```

## Event System

### Key Events

1. **ThreadEvent**
   - MessageAdded
   - SummaryGenerated
   - TokenUsageUpdated
   - ModelChanged

2. **ActiveThreadEvent**
   - ScrollPositionChanged
   - EditingMessageTokenCountChanged

3. **MessageEditorEvent**
   - Changed
   - EstimatedTokenCount
   - ScrollThreadToBottom

### Event Flow Example

```rust
// Subscription to thread events
cx.subscribe(&thread, |panel, thread, event, cx| {
    match event {
        ThreadEvent::MessageAdded(message_id) => {
            // Update UI, scroll to bottom
            panel.update_message_list(cx);
        }
        ThreadEvent::SummaryGenerated => {
            // Update thread title
            panel.update_title(thread.read(cx).summary(), cx);
        }
        // ... other events
    }
});
```

## UI Components

### Message Rendering

Messages are rendered using GPUI components:

```rust
// Message display component
impl ActiveThread {
    fn render_message(&self, message: &Message, cx: &mut Context) -> AnyElement {
        match message.role {
            Role::User => self.render_user_message(message, cx),
            Role::Assistant => self.render_assistant_message(message, cx),
            Role::System => self.render_system_message(message, cx),
        }
    }
}
```

### Tool Call UI

Tool calls have special rendering with:
- Status indicators
- Diff previews
- Confirmation buttons
- Progress tracking

## Integration Points for Mobile

### 1. Data Access Points

To access agent panel data from a mobile app, key integration points include:

```rust
// Access current thread
let thread = agent_panel.active_thread();

// Get message history
let messages = thread.messages();

// Monitor updates
cx.subscribe(&thread, |_, _, event, cx| {
    // Forward events to mobile
});
```

### 2. Command Execution

Mobile commands can be executed through:

```rust
// Send user message
thread.send_message(content, cx);

// Execute slash command
thread.run_slash_command(command, cx);

// Confirm/reject tool calls
thread.update_tool_call_status(id, status, cx);
```

### 3. State Synchronization

Key state to synchronize:
- Active thread ID
- Message list
- Tool call statuses
- Token usage
- Model configuration
- Context items

## Protocol Considerations

### Agent Client Protocol (ACP)

The ACP provides structured communication:

```rust
// Session updates from agent
pub enum SessionUpdate {
    UserMessage(ContentBlock),
    AgentMessageChunk(ContentBlock),
    AgentThoughtChunk(ContentBlock),
    ToolCall(ToolCall),
}

// Content blocks
pub enum ContentBlock {
    Text(String),
    Code { language: String, content: String },
    Image { url: String },
}
```

### Serialization Format

Threads are serialized as JSON with versioning:

```json
{
  "version": "0.2.0",
  "summary": "Thread Title",
  "updated_at": "2024-01-01T00:00:00Z",
  "messages": [...],
  "token_usage": {
    "prompt_tokens": 1000,
    "completion_tokens": 500
  }
}
```

## Performance Considerations

### Memory Management

- Messages are stored in memory with incremental loading
- Large contexts are loaded on-demand
- Tool call diffs are computed lazily

### Rendering Optimization

- Virtual scrolling for long message lists
- Incremental markdown rendering
- Cached syntax highlighting

## Mobile Integration Strategy

### Approach 1: Direct Data Access (Recommended)

Extract agent panel data through Rust FFI:
- Minimal overhead
- Real-time updates
- Direct access to all features

### Approach 2: Protocol Bridge

Implement ACP client in mobile:
- Network-based communication
- Platform independence
- Higher latency

### Approach 3: Event Streaming

Stream events through WebSocket:
- Simple implementation
- Good for read-only monitoring
- Limited interaction capability

## Conclusion

The Zed agent panel is a sophisticated system with:
- Complex state management
- Rich event system
- Flexible architecture
- Strong typing throughout

For mobile integration, the best approach is to:
1. Use Rust FFI for direct data access
2. Stream events through a dedicated channel
3. Implement command execution through structured APIs
4. Maintain state synchronization with incremental updates

This architecture provides a solid foundation for building a mobile companion app that can effectively monitor and interact with Zed's AI assistant.
