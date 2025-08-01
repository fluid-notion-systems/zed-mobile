# Zed Mobile Roadmap

## Overview
This roadmap tracks the implementation progress of Zed Mobile, focusing on agent functionality through collab server integration. The project creates a mobile companion app for Zed's agent panel.

## Development Guidelines

- We will be using hot reload to push to device and also run on desktop
- Make code changes to get a feature working. ONE FEATURE AT A TIME. No oneshotting.
- When a feature works as expected, update the roadmap.md file to check off the task, then git commit and push.

## ✅ Phase 1: Foundation (Completed)

### zed-agent-core Crate
- [x] Create standalone crate without GPUI dependencies
- [x] Implement core data models (Thread, Message, MessageSegment)
- [x] Build EventBus for event distribution
- [x] Add AgentEvent enum with all event types
- [x] Implement serialization traits (Serialize/Deserialize)
- [x] Add comprehensive unit tests

### Desktop Integration
- [x] Create core_conversion.rs for GPUI ↔ Core conversions
- [x] Implement EventBridge to connect GPUI events to EventBus
- [x] Integrate EventBus into existing agent system
- [x] Test event flow from agent actions to EventBus

### Documentation
- [x] Document agent system architecture
- [x] Create implementation plan
- [x] Consolidate redundant documentation
- [x] Update architecture for collab server approach

## 🚧 Phase 2: Collab Server Integration (Current - 4 weeks)

### Protocol Definition (Week 1)
- [ ] Create proto/agent.proto with agent-specific messages
- [ ] Define AgentEvent protobuf messages
- [ ] Define RPC service methods (Subscribe, GetThreads, etc.)
- [ ] Generate Rust code from proto definitions
- [ ] Add proto conversion methods to zed-agent-core

### Server Implementation (Week 2)
- [ ] Add agent subscription management to collab server
- [ ] Implement event routing for agent events
- [ ] Add authentication/authorization checks
- [ ] Handle connection lifecycle and cleanup
- [ ] Implement rate limiting for events
- [ ] Add metrics and monitoring

### Desktop Bridge (Week 3)
- [ ] Create AgentCollabBridge struct
- [ ] Connect EventBus to collab client
- [ ] Implement proto conversion for all event types
- [ ] Add reconnection handling
- [ ] Test end-to-end event flow
- [ ] Handle error cases and recovery

### Testing & Validation (Week 4)
- [ ] Unit tests for subscription management
- [ ] Integration tests for event flow
- [ ] Load tests for high-frequency events
- [ ] Security tests for data isolation
- [ ] Performance benchmarking

## 📱 Phase 3: Mobile MVP - Flutter (6 weeks)

### Week 1: Flutter UI Foundation
- [ ] Project setup with dependencies
- [ ] Basic navigation structure
- [ ] Core UI components
- [ ] Riverpod providers setup
- [ ] AgentState management

### Week 2: Essential Screens
- [ ] SplashScreen (connection status)
- [ ] AgentPanel (main interface)
- [ ] ThreadHistory
- [ ] Settings

### Week 3: UI Components
- [ ] MessageBubble widget
- [ ] ThreadHeader widget
- [ ] MessageInput widget
- [ ] ToolCallCard widget
- [ ] LoadingStates
- [ ] ErrorHandling

### Week 4: Collab Client Integration
- [ ] Implement collab client connection
- [ ] WebSocket management
- [ ] Proto message handling
- [ ] Event stream processing
- [ ] Authentication flow

### Week 5: Core Features
- [ ] Real-time message streaming
- [ ] Thread navigation
- [ ] Command input interface
- [ ] Tool call visualization
- [ ] Message caching
- [ ] Offline support structure

### Week 6: Connection Management
- [ ] Implement reconnection logic
- [ ] Add offline command queue
- [ ] Build sync state management
- [ ] Handle network transitions
- [ ] Add connection status UI

## 🎨 Phase 4: Polish & iOS Native (4 weeks)

### iOS Native Client
- [ ] SwiftUI implementation
- [ ] Native collab client
- [ ] Platform-specific features
- [ ] Accessibility support
- [ ] Dark mode support

### UI/UX Refinement
- [ ] Animations and transitions
- [ ] Gesture support
- [ ] Haptic feedback
- [ ] Error states
- [ ] Empty states

### Performance Optimization
- [ ] Memory profiling
- [ ] Battery optimization
- [ ] Network efficiency
- [ ] UI performance
- [ ] Caching strategies

### Beta Testing
- [ ] TestFlight setup
- [ ] Crash reporting
- [ ] Analytics integration
- [ ] User feedback collection

## 🤖 Phase 5: Android & Cross-Platform (3 weeks)

### Android Client
- [ ] Kotlin/Compose implementation
- [ ] Material 3 design
- [ ] Platform-specific features
- [ ] Play Store preparation

### Cross-Platform Features
- [ ] Ensure feature parity
- [ ] Shared business logic
- [ ] Consistent UX
- [ ] Platform testing

## 🚀 Phase 6: Advanced Features (4 weeks)

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
- [ ] Diff visualization

### Enhanced Tool Integration
- [ ] Tool call UI refinement
- [ ] File tree browser
- [ ] Context picker
- [ ] Tool status tracking

### Multi-Device Support
- [ ] Cross-device state sync
- [ ] Handoff between devices
- [ ] Shared session support
- [ ] Conflict resolution

### Notifications
- [ ] Push notification setup
- [ ] Smart notification filtering
- [ ] Background sync
- [ ] Notification actions

## 🌐 Phase 7: Web Client (3 weeks)

### Web Implementation
- [ ] Create web client project
- [ ] Implement WebSocket connection
- [ ] Build responsive UI
- [ ] Add PWA support
- [ ] Deploy to production

## 📊 Success Metrics

### Technical Metrics
- [ ] < 100ms UI response time
- [ ] < 100ms event latency (local network)
- [ ] < 500ms event latency (internet)
- [ ] < 50MB memory usage
- [ ] < 5% battery impact
- [ ] > 99% crash-free rate
- [ ] > 90% message delivery rate

### User Metrics
- [ ] > 4.5 app store rating
- [ ] > 80% user retention (30 days)
- [ ] < 2s app launch time
- [ ] > 80% user satisfaction score
- [ ] > 95% successful reconnection rate

### Scale Metrics
- [ ] Support for 10K+ concurrent users
- [ ] 99.9% uptime for collab service
- [ ] < 1% message loss rate

## 🚦 Release Milestones

### M1: Internal Alpha (Phase 2 completion)
- Collab server integration complete
- Desktop sending events successfully
- Basic monitoring in place

### M2: Flutter Beta (Phase 3 completion)
- Flutter client functional
- Core features working
- Limited beta user group
- TestFlight/Play Console beta

### M3: Native Clients (Phase 4-5 completion)
- iOS SwiftUI client available
- Android Compose client available
- Feature-complete for agent panel
- Public beta program

### M4: General Availability (Phase 6 completion)
- All platforms supported
- Advanced features enabled
- Performance targets met
- Production-ready

### M5: Web Launch (Phase 7 completion)
- Web client available
- PWA support
- Full feature parity

## ⚠️ Risk Mitigation

### Technical Risks
- **Collab server scalability**
  - Mitigation: Load testing early
  - Fallback: Implement caching layers

- **Mobile battery impact**
  - Mitigation: Aggressive optimization
  - Fallback: Configurable sync intervals

- **Network reliability**
  - Mitigation: Robust offline support
  - Fallback: Local-only mode

- **Flutter performance**
  - Mitigation: Native implementations where needed
  - Fallback: Platform-specific optimizations

### Project Risks
- **Scope creep**
  - Mitigation: Strict phase boundaries
  - Fallback: Feature flags

- **Timeline delays**
  - Mitigation: Buffer time included
  - Fallback: Phased releases

- **Zed API changes**
  - Mitigation: Version pinning
  - Fallback: Compatibility layer

## 🔮 Future Roadmap (Post-Launch)

### Version 1.1 (Month 2)
- Terminal panel integration
- iPad/tablet optimization
- Additional language models
- Workspace sync

### Version 1.2 (Month 3)
- Diagnostics panel
- Search results panel
- Team collaboration
- Analytics dashboard

### Version 2.0 (Month 6)
- Full Zed integration
- Remote development
- Plugin ecosystem
- Custom panel API
- Multi-user sessions

### Enterprise Edition
- SSO integration
- Audit logging
- Compliance tools
- Private cloud deployment
- Role-based permissions

## 📦 Dependencies

### External Dependencies
- Zed team approval for collab server changes
- Protocol buffer toolchain
- Flutter SDK
- SwiftUI/Xcode (iOS)
- Android Studio (Android)
- Mobile app store accounts
- Cloud infrastructure setup

### Internal Dependencies
- zed-agent-core stability
- Collab server API stability
- Desktop agent implementation
- Testing infrastructure

### Development Tools
- Hot reload setup
- Device testing lab
- CI/CD pipeline
- Crash reporting service
- Analytics platform

## 👥 Team & Resources

### Required Skills
- Rust development (collab server)
- Flutter development (UI, state)
- iOS development (SwiftUI)
- Android development (Compose)
- Protocol buffers
- WebSocket expertise
- UI/UX design

### Recommended Team
- 1 Rust developer (collab server)
- 2 Flutter developers
- 1 iOS developer
- 1 Android developer
- 1 UI/UX designer
- 1 QA engineer

## 📝 Notes

- All timelines are estimates and subject to change
- Each phase includes testing and documentation
- Security review required before each release
- Performance benchmarks at each milestone
- One feature at a time - incremental development
- Regular commits after each working feature