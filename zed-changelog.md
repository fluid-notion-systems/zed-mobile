# Zed Changelog

This changelog tracks modifications made to the vendored Zed codebase for the mobile integration.

## 2024-01-XX - Agent Proto Definitions

### Context
After initially implementing zed-agent-core integration with event bridge and core type conversions, we decided to change approach. The zed-agent-core related commits were backed out cleanly using git reset and cherry-pick to preserve only the proto definitions.

### Added

#### Proto Definitions (`vendor/zed/crates/proto/proto/agent.proto`)
- Created comprehensive protobuf definitions for all agent-related structures:
  - Core types: `ThreadId`, `PromptId`, `MessageId`, `Thread`, `AgentMessage`, `MessageSegment`
  - State management: `ThreadSummary`, `DetailedSummaryState`, `QueueState`, `ThreadCheckpoint`
  - Token usage: `TokenUsage`, `TotalTokenUsage`, `TokenUsageRatio`, `ExceededWindowError`
  - Tool integration: `ToolUseSegment`, `PendingToolUse`, `ToolUseStatus`
  - Events: `ThreadEvent` with comprehensive event types
  - RPC messages for agent operations (subscribe, create thread, send message, etc.)

#### Proto Conversion Module Stub (`vendor/zed/crates/agent/src/proto/mod.rs`)
- Added placeholder module for future proto conversions
- Currently contains conversion implementations between agent crate types and proto messages
- Includes helper function `thread_to_proto()` (to be completed when event routing is implemented)

#### Proto Registration (`vendor/zed/crates/proto/src/proto.rs`)
- Added agent messages to the `messages!` macro:
  - `SubscribeToAgentEvents`, `UnsubscribeFromAgentEvents`, `AgentEventNotification`
  - Thread operations: `GetAgentThreads`, `GetAgentThread`, `CreateAgentThread`
  - Message operations: `SendAgentMessage`, `CancelAgentCompletion`
  - Tool operations: `UseAgentTools`, `DenyAgentTools`
  - Checkpoint operations: `RestoreThreadCheckpoint`
- Added request/response pairs to `request_messages!` macro

### Modified

#### Agent Module (`vendor/zed/crates/agent/src/agent.rs`)
- Added `pub mod proto;` to expose the proto conversion module

### Removed (via git reset)
- `zed-agent-core` crate dependency and all related code
- `event_bridge` module and EventBridge implementation
- `core_conversion` module
- `to_core()` and `messages_to_core()` methods from Thread
- All `Into<zed_agent_core::*>` trait implementations

#### Proto Build Fixes
- Renamed `Message` to `AgentMessage` in agent.proto to avoid conflict with prost's `Message` trait
- Renamed `Stopped` to `AgentStopped` in agent.proto to avoid conflict with debugger.proto's `DapThreadStatus::Stopped`
- Replaced `google.protobuf.Timestamp` with Zed's custom `Timestamp` message to avoid serde serialization issues
- Updated imports from `import "google/protobuf/timestamp.proto"` to `import "worktree.proto"`
- Added all agent RPC messages to the Envelope in zed.proto (messages 368-379)

### Technical Notes

- The proto definitions support all major agent functionality including:
  - Real-time message streaming
  - Tool use confirmation and execution
  - Thread state management and checkpoints
  - Token usage tracking and limits
  - Git state snapshots for checkpoints
  - Multiple message segment types (Text, Thinking, RedactedThinking)
  
- The conversion module provides type-safe conversions with proper error handling
- All proto messages include serde serialization support via the build configuration
- The integration maintains backward compatibility with optional fields in proto3

### Build and Test Status

The proto build now completes successfully:
```bash
cd vendor/zed/crates/proto && cargo build
# Finished `dev` profile [unoptimized + debuginfo] target(s) in 34.77s
```

### TODO

The proto conversion module currently contains placeholder implementations. Full conversions will be implemented when the event routing and collab server handlers are added in Stage 2.

### Git History Note

The following commits were backed out to remove zed-agent-core dependencies:
- `2706750aa8` integration tests for event_bridge  
- `bce2d4aad5` updates
- `1bedc5a6e2` feat(agent): Implement EventBridge for core event system integration
- `edcac123d3` feat(agent): Add core type usage in Thread serialization
- `8