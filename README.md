# Zed Mobile

A mobile companion app for monitoring and interacting with Zed's runtime, with initial focus on the agentic panel for real-time AI assistant monitoring and control.

## Overview

Zed Mobile provides a mobile interface to observe and interact with various aspects of the Zed editor runtime. The initial release focuses on the agentic panel, allowing users to monitor AI assistant activities, view panel outputs, and send commands through voice or text input.

## Features

### Phase 1: Agentic Panel Monitor (MVP)
- **Real-time Panel Output**: Stream and display agentic panel outputs directly on mobile
- **Voice Input**: Send commands to the AI assistant using voice recognition
- **Text Input**: Traditional text-based command input
- **Activity Monitoring**: Track AI assistant actions, tool calls, and responses
- **Session History**: Browse through past interactions and sessions
- **Push Notifications**: Get alerts for important AI assistant events

### Future Phases
- **Multi-Panel Support**: Extend to other Zed panels (terminal, diagnostics, etc.)
- **Remote Control**: Execute editor commands from mobile
- **Collaborative Features**: Share AI sessions with team members
- **Analytics Dashboard**: Visualize AI assistant usage patterns
- **Workspace Sync**: Access multiple Zed workspace configurations

## Architecture Options

### Option 1: Flutter + Zed Extension
- **Mobile App**: Flutter (cross-platform iOS/Android)
- **Communication**: WebSocket/gRPC connection to Zed extension
- **Zed Extension**: Custom extension exposing runtime data via API
- **Benefits**: Platform independence, rapid development, existing Flutter ecosystem

### Option 2: Native Kotlin + Zed Extension
- **Mobile App**: Kotlin Multiplatform Mobile (KMM)
- **Communication**: Protocol Buffers over WebSocket
- **Zed Extension**: Rust-based extension with proto definitions
- **Benefits**: Better performance, native platform features, shared business logic

### Option 3: Direct Zed Integration
- **Mobile Component**: Embedded within Zed codebase
- **Communication**: Direct IPC/shared memory
- **Architecture**: Zed as a service with mobile client
- **Benefits**: Tightest integration, no extension overhead, unified codebase

## Technology Stack

### Mobile App
- **UI Framework**: Flutter 3.x / Jetpack Compose
- **State Management**: Riverpod (Flutter) / Flow (Kotlin)
- **Voice Recognition**: Google Speech-to-Text / iOS Speech Framework
- **Networking**: Dio (Flutter) / Ktor (Kotlin)
- **Local Storage**: Hive/SQLite

### Zed Extension
- **Language**: Rust
- **Protocol**: gRPC with Protocol Buffers
- **WebSocket**: tokio-tungstenite
- **Serialization**: serde with bincode/JSON

### Communication Protocol
```protobuf
// Example protocol definition
message AgentPanelUpdate {
    string session_id = 1;
    oneof content {
        UserMessage user_message = 2;
        AssistantMessage assistant_message = 3;
        ToolCall tool_call = 4;
        SystemEvent system_event = 5;
    }
    int64 timestamp = 6;
}
```

## Getting Started

### Prerequisites
- Zed editor (latest version)
- Flutter SDK 3.x or Kotlin development environment
- Rust toolchain (for extension development)
- Mobile device or emulator for testing

### Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/zed-mobile.git
   cd zed-mobile
   ```

2. **Run the mobile app**
   ```bash
   flutter run
   ```

## Project Structure

```
zed-mobile/
├── lib/                   # Flutter app source code
│   ├── main.dart         # App entry point
│   ├── screens/          # UI screens
│   ├── widgets/          # Reusable UI components
│   └── models/           # Data models
├── android/              # Android-specific code
├── ios/                  # iOS-specific code
├── research/             # Research documents and findings
├── docs/                 # Documentation
└── README.md            # This file
```

## Development Roadmap

### Milestone 1: Basic Flutter App (Week 1)
- [x] Set up Flutter project structure
- [ ] Create basic UI screens (splash, agent panel, settings)
- [ ] Implement simple navigation
- [ ] Test on physical device

### Milestone 2: Agent Panel UI (Week 2)
- [ ] Message bubble components
- [ ] Thread history display
- [ ] Text input functionality
- [ ] Mock data integration

### Milestone 3: Real Data Integration (Week 3-4)
- [ ] Zed extension development
- [ ] WebSocket communication
- [ ] Real-time message streaming
- [ ] Error handling

### Milestone 4: Enhanced Features (Week 5-6)
- [ ] Voice input integration
- [ ] Push notifications
- [ ] Settings and configuration
- [ ] Performance optimization

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:
- Code style and standards
- Pull request process
- Testing requirements
- Documentation guidelines

## Research

See the [research directory](./research/) for:
- [Mobile Architecture Comparison](./research/mobile-architecture.md)
- [Zed Extension API Analysis](./research/zed-extension-api.md)
- [Voice Input Technologies](./research/voice-input.md)
- [Real-time Communication Protocols](./research/realtime-protocols.md)

## Documentation

- [Using Zed's Local Collaboration Server](./docs/zed-local-collab.md) - How to use the existing Zed collaboration server for mobile development

## License

This project is licensed under the same terms as Zed. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Zed team for the excellent editor and extension API
- Contributors and early testers
- Open source libraries and frameworks used in this project