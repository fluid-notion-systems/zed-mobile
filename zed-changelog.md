# Zed Changelog

This changelog tracks modifications made to the vendored Zed codebase for the mobile integration.

## 2024-01-XX - Agent Proto Integration

### Added

#### Proto Definitions (`vendor/zed/crates/proto/proto/agent.proto`)
- Created comprehensive protobuf definitions for all agent-related structures:
  - Core types: `ThreadId`, `PromptId`, `MessageId`, `Thread`, `Message`, `MessageSegment`
  - State management: `ThreadSummary`, `DetailedSummaryState`, `QueueState`, `ThreadCheckpoint`
  - Token usage: `TokenUsage`, `TotalTokenUsage`, `TokenUsageRatio`, `ExceededWindowError`
  - Tool integration: `ToolUseSegment`, `PendingToolUse`, `ToolUseStatus`
  - Events: `ThreadEvent`, `AgentEvent` with comprehensive event types
  - RPC messages for agent operations (subscribe, create thread, send message, etc.)

#### Proto Conversion Module (`vendor/zed/crates/agent/src/proto/mod.rs`)
- Added bidirectional conversion implementations between Rust types and Proto messages
- Helper functions for thread serialization (`thread_to_proto()`)
- Role conversions with error handling
- Unit tests for core conversions

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

#### Build Configuration (`vendor/zed/crates/zed-agent-core/Cargo.toml`)
- Fixed circular dependency in proto feature: changed `proto = ["proto", "anyhow"]` to `proto = ["dep:proto", "anyhow"]`

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

### TODO

The following conversions are marked as TODO in the proto module and may need implementation:
- `LoadedContext` conversion
- `AgentContextHandle` conversion  
- `PendingCompletion` conversion
- `ConfiguredModel` conversion
- `DetailedSummaryState` full implementation
- `ProjectSnapshot` conversion