# Local Collaboration Server for Zed Mobile

## Overview

This document explores how to leverage Zed's existing collaboration infrastructure (collab server, RPC, LiveKit) to enable local network collaboration between Zed desktop and mobile clients. Rather than building a new WebSocket server from scratch, we can reuse the battle-tested collab server components.

## Current Architecture Analysis

### Existing Components

1. **Collab Server** (`crates/collab`)
   - Full-featured collaboration server with WebSocket support
   - RPC protocol implementation
   - Room management and presence
   - LiveKit integration for audio/video
   - Authentication and authorization
   - Database layer (can use SQLite for local)

2. **RPC System** (`crates/rpc`)
   - Peer-to-peer connection management
   - Message routing and handling
   - Protobuf-based protocol
   - Connection pooling
   - Automatic reconnection

3. **Client Integration** (`crates/client`)
   - Connection management
   - Authentication handling
   - Channel subscriptions
   - Project sharing

## Proposed Approach: Local Collab Mode

### 1. Lightweight Local Server

Instead of creating a new server, we can run a minimal version of the collab server locally:

```rust
// Local collaboration server configuration
pub struct LocalCollabConfig {
    pub port: u16,
    pub database_url: String, // SQLite in-memory or file
    pub require_auth: bool,   // Can be disabled for local network
    pub enable_livekit: bool, // Optional for voice/video
}

impl Default for LocalCollabConfig {
    fn default() -> Self {
        Self {
            port: 45454,
            database_url: "sqlite::memory:?mode=rwc".to_string(),
            require_auth: false,
            enable_livekit: false,
        }
    }
}
```

### 2. Server Startup in Zed

Add a new command to start local collaboration:

```rust
// In zed/src/main.rs or a new local_collab module
pub async fn start_local_collaboration(cx: &mut App) -> Result<()> {
    let config = LocalCollabConfig::default();
    
    // Start embedded collab server
    let server = collab::Server::new_local(config).await?;
    
    // Advertise via mDNS/Bonjour
    let mdns = start_mdns_advertisement(server.port()).await?;
    
    // Show UI notification
    cx.notify("Local collaboration server started on port 45454");
    
    // Store server handle for cleanup
    cx.set_global(LocalCollabServer { server, mdns });
    
    Ok(())
}
```

### 3. Mobile Discovery and Connection

The mobile app can discover local Zed instances:

```dart
// Flutter implementation
class LocalZedDiscovery {
  final _mdns = MDnsClient();
  
  Stream<ZedInstance> discoverLocalInstances() async* {
    await _mdns.start();
    
    await for (final PtrResourceRecord ptr in _mdns.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_zed-collab._tcp.local'),
    )) {
      // Resolve service details
      final srv = await _resolveSrv(ptr.domainName);
      yield ZedInstance(
        name: ptr.name,
        host: srv.host,
        port: srv.port,
        version: await _getVersion(srv.host, srv.port),
      );
    }
  }
}
```

### 4. Simplified Authentication

For local collaboration, we can use a simplified auth flow:

```rust
// Local auth provider
pub struct LocalAuthProvider {
    shared_secret: String,
}

impl LocalAuthProvider {
    pub fn new() -> Self {
        // Generate a one-time secret shown in desktop UI
        let secret = generate_pairing_code();
        Self { shared_secret: secret }
    }
    
    pub async fn authenticate(&self, token: &str) -> Result<User> {
        if token == self.shared_secret {
            Ok(User {
                id: 1,
                email: "local@zed.dev",
                name: "Local User",
                // ... other fields
            })
        } else {
            Err(anyhow!("Invalid pairing code"))
        }
    }
}
```

## Implementation Plan

### Phase 1: Desktop Local Server Mode

1. **Add Local Server Mode to Collab**
   ```rust
   // In collab/src/main.rs
   Some("serve-local") => {
       let config = LocalCollabConfig::from_env()?;
       let app_state = AppState::new_local(config).await?;
       serve_local(app_state).await?;
   }
   ```

2. **Minimal Database Schema**
   - Only essential tables (users, rooms, projects)
   - In-memory SQLite by default
   - No billing, analytics, or external services

3. **mDNS Advertisement**
   ```rust
   use mdns_sd::{ServiceDaemon, ServiceInfo};
   
   pub fn advertise_local_server(port: u16) -> Result<ServiceDaemon> {
       let mdns = ServiceDaemon::new()?;
       let service = ServiceInfo::new(
           "_zed-collab._tcp.local.",
           "Zed Local",
           &format!("{}.local.", hostname()),
           port,
           &[("version", VERSION)],
       )?;
       mdns.register(service)?;
       Ok(mdns)
   }
   ```

### Phase 2: Mobile Client Integration

1. **Service Discovery UI**
   - List discovered Zed instances
   - Pairing code input
   - Connection status

2. **RPC Client Adaptation**
   - Use existing RPC protocol
   - Connect to local server instead of cloud
   - Handle connection lifecycle

3. **Agent Panel Integration**
   - Subscribe to agent events via RPC
   - Display in mobile UI
   - Send commands back

### Phase 2.5: Agent Event Integration

1. **Add Agent Events to RPC Protocol**
   ```protobuf
   // In rpc/proto/zed.proto
   message AgentEventStream {
       oneof event {
           ThreadCreated thread_created = 1;
           ThreadUpdated thread_updated = 2;
           MessageAdded message_added = 3;
           MessageStreaming message_streaming = 4;
           ToolUseStarted tool_use_started = 5;
       }
   }
   
   message SubscribeToAgentEvents {}
   
   message UnsubscribeFromAgentEvents {}
   ```

2. **Server-Side Event Streaming**
   ```rust
   // In collab server
   impl Server {
       async fn handle_subscribe_to_agent_events(
           &self,
           request: TypedEnvelope<SubscribeToAgentEvents>,
           session: &Session,
       ) -> Result<()> {
           // Subscribe to the global agent event bus
           let event_bus = agent::event_bus();
           let subscription = event_bus.subscribe();
           
           // Store subscription for this connection
           session.agent_subscriptions.insert(subscription);
           
           // Stream events to client
           tokio::spawn(async move {
               while let Ok(event) = subscription.recv().await {
                   let rpc_event = convert_to_rpc_event(event);
                   session.peer.send(session.connection_id, rpc_event).await?;
               }
           });
           
           Ok(())
       }
   }
   ```

3. **Mobile Client Event Handling**
   ```dart
   // Flutter RPC client
   class AgentEventStream {
       final RpcClient _client;
       final _eventController = StreamController<AgentEvent>.broadcast();
       
       Stream<AgentEvent> get events => _eventController.stream;
       
       Future<void> subscribe() async {
           await _client.send(SubscribeToAgentEvents());
           
           _client.messages
               .where((msg) => msg is AgentEventStream)
               .listen((event) {
                   _eventController.add(parseAgentEvent(event));
               });
       }
   }
   ```

4. **Event Bridge Integration**
   ```rust
   // Connect EventBridge to RPC streaming
   impl LocalCollabServer {
       fn setup_agent_bridge(&self) {
           let event_bus = agent::event_bus();
           let server = self.server.clone();
           
           // Forward all agent events to connected clients
           event_bus.subscribe_all(move |event| {
               server.broadcast_to_agent_subscribers(event);
           });
       }
   }
   ```

### Phase 3: Enhanced Features

1. **Project Sharing**
   - Share entire projects between desktop and mobile
   - File synchronization
   - Collaborative editing

2. **Voice/Video (Optional)**
   - Local LiveKit server
   - Direct peer-to-peer WebRTC
   - Screen sharing

3. **Security Enhancements**
   - TLS with self-signed certificates
   - Token rotation
   - Network isolation options

4. **Agent-Specific Features**
   - Command execution from mobile
   - Tool use coordination
   - Shared context between devices
   - Multi-device agent sessions

## Advantages Over Custom WebSocket Server

1. **Reuse Existing Code**
   - Battle-tested RPC protocol
   - Proven connection handling
   - Existing message types

2. **Full Feature Set**
   - Room management
   - Presence awareness
   - Project sharing
   - Collaborative editing

3. **Upgrade Path**
   - Easy transition to cloud collaboration
   - Same client code for local/cloud
   - Consistent user experience

4. **Maintenance**
   - Single codebase for local/cloud
   - Shared bug fixes and improvements
   - Better test coverage

## Technical Considerations

### Performance

- Local network latency: ~1-5ms
- No database replication needed
- Direct file system access
- Minimal overhead

### Security

- Local network only by default
- Optional authentication
- Encrypted connections (TLS)
- Firewall considerations

### Cross-Platform

- mDNS works on all platforms
- SQLite is universal
- Same RPC protocol everywhere

## Migration from Current Approach

Instead of building a custom WebSocket bridge in the extension system:

1. **Embed Collab Server**
   - Link collab as library
   - Start on demand
   - Minimal configuration

2. **Adapt Mobile Client**
   - Use existing RPC client
   - Add local discovery
   - Same message handling

3. **Gradual Migration**
   - Start with agent events
   - Add features incrementally
   - Maintain compatibility

## Conclusion

Leveraging the existing collab server infrastructure provides a more robust, feature-complete solution for local collaboration. It reduces code duplication, provides an upgrade path to cloud collaboration, and ensures consistency across the platform.

The main development effort would be:
1. Making collab server embeddable and lightweight
2. Adding local discovery mechanisms
3. Adapting the mobile client to use RPC instead of custom WebSocket
4. Extending RPC protocol with agent event types
5. Bridging the agent event bus to RPC streaming

This approach aligns better with Zed's architecture and provides a superior user experience. The agent events would flow naturally through the same RPC connection used for other collaboration features, providing a unified communication channel.

## Next Steps

1. **Prototype Embedded Collab Server**
   - Extract minimal collab server
   - Add local-only mode
   - Test with SQLite

2. **Extend RPC Protocol**
   - Add agent event messages
   - Implement streaming handlers
   - Test event flow

3. **Mobile Client Proof of Concept**
   - RPC client implementation
   - Agent event display
   - Basic command sending

This approach provides a solid foundation for both immediate agent integration and future full collaboration features.