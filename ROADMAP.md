# Zed Mobile Development Roadmap

## Overview

This roadmap outlines the development phases for Zed Mobile, focusing on creating a mobile companion app for Zed's agentic panel. The project is divided into four main tracks that can partially run in parallel.

## Development Guidelines

- we will be using hotrun(?) to push to my device, and also run in desktop, hotrun both
- Make code changes to get a feature working. ONE FEATURE AT A TIME. no oneshotting.
- When i indicate that the app works as expected, update the ROADMAP.md file to check off the task, and git commit and push.

## Phase 1: Basic UI (Weeks 1-2)

### Flutter UI Foundation
- [x] Project setup with dependencies
- [x] Basic navigation structure
- [ ] Core UI components

### Essential Screens
```dart
// Core screens:
- SplashScreen (connection status)
- AgentPanel (main interface)
- ThreadHistory
- Settings
```

### UI Components
- [ ] MessageBubble widget
- [ ] ThreadHeader widget
- [ ] MessageInput widget
- [ ] ToolCallCard widget
- [ ] LoadingStates
- [ ] ErrorHandling

### State Management
- [ ] Riverpod providers setup
- [ ] AgentState management
- [ ] Message caching
- [ ] Offline support structure

### Deliverables
- Basic functional UI
- Component library
- State management architecture

## Phase 2: Foundation & Research (Weeks 3-4)

### Research & Architecture
- [ ] Analyze Zed's agent panel implementation
- [ ] Document GPUI dependencies to remove
- [ ] Design GPUI-free architecture
- [ ] Refine project structure

### Deliverables
- Architecture decision document
- Initial project scaffolding
- Research documentation

## Phase 3: Data Structure Extraction (Weeks 5-6)

### Extract Core Types
- [ ] Create `zed-agent-core` crate without GPUI dependencies
- [ ] Extract Thread, Message, and ToolCall structures
- [ ] Remove Entity<T> and Context<T> wrappers
- [ ] Implement serialization for all types

### Implementation Tasks
```rust
// Key structures to extract:
- Thread, ThreadId, ThreadSummary
- Message, MessageId, MessageSegment
- ToolCall, ToolCallStatus
- AgentContext, ContextId
- TokenUsage, ThreadError
```

### Testing
- [ ] Unit tests for all extracted types
- [ ] Serialization/deserialization tests
- [ ] Memory safety tests

### Deliverables
- `zed-agent-core` crate
- Type documentation
- Test suite

## Phase 4: FFI Bridge (Weeks 7-8)

### Bridge Implementation
- [ ] Create `zed-mobile-bridge` crate
- [ ] Implement C-compatible FFI layer
- [ ] Add memory management utilities
- [ ] Create event streaming system

### Core Functions
```rust
// Essential FFI functions:
- zed_mobile_init()
- zed_mobile_create_thread()
- zed_mobile_send_message()
- zed_mobile_get_messages()
- zed_mobile_subscribe_events()
- zed_mobile_poll_event()
```

### Platform Integration
- [ ] iOS static library build
- [ ] Android shared library build
- [ ] Flutter FFI bindings
- [ ] Memory leak detection

### Deliverables
- Platform libraries (.a, .so)
- Flutter dart:ffi bindings
- FFI documentation
- Memory management guide

## Phase 5: Network Communication (Weeks 9-10)

### Zed Extension Development
- [ ] Create Zed extension for mobile bridge
- [ ] Implement WebSocket server in extension
- [ ] Add authentication mechanism
- [ ] Create protocol specification

### Communication Protocol
```typescript
// Protocol messages:
interface AgentUpdate {
  type: 'message' | 'toolCall' | 'status'
  threadId: string
  payload: any
  timestamp: number
}
```

### Network Features
- [ ] WebSocket connection management
- [ ] Automatic reconnection
- [ ] Message queuing
- [ ] Compression (optional)
- [ ] TLS encryption

### Mobile Integration
- [ ] WebSocket client in Flutter
- [ ] Network status monitoring
- [ ] Sync state management
- [ ] Push notifications setup

### Deliverables
- Zed extension package
- Protocol documentation
- Network architecture diagram

## Phase 6: Advanced Features (Weeks 11-12)

### Voice Input
- [ ] Platform-specific voice APIs
- [ ] Voice command parsing
- [ ] "Hey Zed" wake word
- [ ] Continuous dictation

### Rich Content
- [ ] Markdown rendering
- [ ] Syntax highlighting
- [ ] Image support
- [ ] File preview

### Tool Integration
- [ ] Tool call UI refinement
- [ ] Diff visualization
- [ ] File tree browser
- [ ] Context picker

### Collaboration
- [ ] Multi-device sync
- [ ] Share conversations
- [ ] Export functionality

### Deliverables
- Feature-complete app
- User documentation
- API documentation

## Phase 7: Polish & Optimization (Weeks 13-14)

### Performance
- [ ] Memory profiling
- [ ] Battery optimization
- [ ] Network efficiency
- [ ] UI performance

### Quality
- [ ] Comprehensive testing
- [ ] Accessibility audit
- [ ] Security review
- [ ] Code cleanup

### Platform Polish
- [ ] iOS-specific features
- [ ] Android-specific features
- [ ] Tablet optimization
- [ ] Dark mode refinement

### Deliverables
- Optimized application
- Performance benchmarks
- Security audit report

## Phase 8: Beta & Launch (Weeks 15-16)

### Beta Testing
- [ ] Internal testing
- [ ] Closed beta program
- [ ] Feedback collection
- [ ] Bug fixing

### Launch Preparation
- [ ] App store assets
- [ ] Marketing materials
- [ ] Documentation website
- [ ] Support infrastructure

### Release
- [ ] App store submission
- [ ] Launch announcement
- [ ] Community outreach
- [ ] Post-launch monitoring

## Parallel Development Tracks

### Track A: Core Development
Weeks 1-8: Basic UI → Foundation → Data Structures → FFI

### Track B: Zed Integration
Weeks 5-10: Extension Development → Network Protocol → Testing

### Track C: Mobile Features
Weeks 7-14: UI Development → Advanced Features → Polish

### Track D: Infrastructure
Weeks 1-16: CI/CD → Testing → Documentation → Release

## Risk Mitigation

### Technical Risks
1. **GPUI Extraction Complexity**
   - Mitigation: Start with minimal features
   - Fallback: Use simplified data models

2. **FFI Memory Management**
   - Mitigation: Extensive testing
   - Fallback: Conservative memory strategies

3. **Network Reliability**
   - Mitigation: Offline-first design
   - Fallback: Local-only mode

### Schedule Risks
1. **Zed API Changes**
   - Mitigation: Version pinning
   - Fallback: Maintain compatibility layer

2. **Platform Issues**
   - Mitigation: Early platform testing
   - Fallback: Platform-specific workarounds

## Success Metrics

### Technical Metrics
- [ ] < 100ms UI response time
- [ ] < 50MB memory usage
- [ ] > 99% crash-free rate
- [ ] < 5% battery impact

### User Metrics
- [ ] > 4.5 app store rating
- [ ] > 80% user retention (30 days)
- [ ] < 2s app launch time
- [ ] > 90% message delivery rate

## Future Roadmap (Post-Launch)

### Version 1.1 (Month 2)
- Multi-panel support
- iPad optimization
- Additional language models

### Version 1.2 (Month 3)
- Workspace sync
- Team collaboration
- Analytics dashboard

### Version 2.0 (Month 6)
- Full Zed integration
- Remote development
- Plugin ecosystem

## Team & Resources

### Required Skills
- Rust development (FFI, systems)
- Flutter development (UI, state)
- Zed extension development
- Mobile platform expertise
- UI/UX design

### Recommended Team
- 1 Rust developer (lead)
- 2 Flutter developers
- 1 Zed integration developer
- 1 UI/UX designer
- 1 QA engineer

## Conclusion

This roadmap provides a structured approach to building Zed Mobile with clear milestones and deliverables. The modular design allows for parallel development and risk mitigation while ensuring a high-quality mobile experience for Zed users.
