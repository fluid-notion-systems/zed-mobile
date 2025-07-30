# Zed Mobile Technical Implementation Roadmap

## Overview

This technical roadmap provides detailed implementation steps for each component of Zed Mobile. Each section includes specific code structures, dependencies, and technical decisions.

## Phase 1: Data Structure Extraction

### Week 1: Analysis and Planning

#### 1.1 Dependency Analysis
```bash
# Analyze GPUI dependencies in agent crates
cd vendor/zed
cargo tree -p agent --no-dedupe | grep gpui
cargo tree -p agent_ui --no-dedupe | grep gpui
```

#### 1.2 Create Extraction Plan
- Map all GPUI types to replacements
- Identify Entity<T> usage patterns
- Document Context<T> dependencies
- Plan event system replacement

### Week 2: Core Type Extraction

#### 2.1 Create New Crate Structure
```toml
# zed-mobile/core/Cargo.toml
[package]
name = "zed-agent-core"
version = "0.1.0"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1.0", features = ["serde"] }
anyhow = "1.0"
```

#### 2.2 Extract Core Types
```rust
// core/src/thread.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Thread {
    pub id: ThreadId,
    pub summary: String,
    pub messages: Vec<Message>,
    pub updated_at: DateTime<Utc>,
    pub token_usage: TokenUsage,
    #[serde(skip)]
    pub dirty: bool,
}

// core/src/message.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: MessageId,
    pub role: MessageRole,
    pub content: MessageContent,
    pub timestamp: DateTime<Utc>,
    pub tool_calls: Vec<ToolCall>,
}

// core/src/tool_call.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: serde_json::Value,
    pub status: ToolCallStatus,
    pub result: Option<ToolCallResult>,
}
```

## Phase 2: FFI Bridge Implementation

### Week 3: Bridge Architecture

#### 3.1 Bridge Crate Setup
```toml
# bridge/Cargo.toml
[package]
name = "zed-mobile-bridge"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
zed-agent-core = { path = "../core" }
tokio = { version = "1", features = ["rt-multi-thread"] }
once_cell = "1.19"
parking_lot = "0.12"
log = "0.4"

[build-dependencies]
cbindgen = "0.26"
```

#### 3.2 Runtime Management
```rust
// bridge/src/runtime.rs
pub struct ZedRuntime {
    tokio_runtime: tokio::runtime::Runtime,
    agent_manager: Arc<Mutex<AgentManager>>,
    event_queue: Arc<Mutex<VecDeque<AgentEvent>>>,
}

impl ZedRuntime {
    pub fn new() -> Result<Self> {
        let tokio_runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()?;

        Ok(Self {
            tokio_runtime,
            agent_manager: Arc::new(Mutex::new(AgentManager::new())),
            event_queue: Arc::new(Mutex::new(VecDeque::with_capacity(1000))),
        })
    }
}
```

### Week 4: FFI Functions

#### 4.1 Core FFI API
```rust
// bridge/src/ffi.rs
#[repr(C)]
pub struct FfiResult {
    success: bool,
    error_code: i32,
    error_message: *const c_char,
    data: *mut c_void,
}

#[no_mangle]
pub extern "C" fn zed_mobile_init() -> FfiResult {
    match ZedRuntime::initialize() {
        Ok(_) => FfiResult::success(),
        Err(e) => FfiResult::error(-1, &e.to_string()),
    }
}

#[no_mangle]
pub extern "C" fn zed_mobile_create_thread() -> *mut c_char {
    with_runtime(|runtime| {
        runtime.create_thread()
            .map(|id| CString::new(id.to_string()).unwrap().into_raw())
            .unwrap_or(std::ptr::null_mut())
    })
}
```

#### 4.2 Event Streaming
```rust
// bridge/src/events.rs
#[no_mangle]
pub extern "C" fn zed_mobile_poll_events(
    buffer: *mut u8,
    buffer_size: usize,
) -> i32 {
    with_runtime(|runtime| {
        if let Some(event) = runtime.poll_event() {
            let json = serde_json::to_vec(&event).unwrap();
            if json.len() <= buffer_size {
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        json.as_ptr(),
                        buffer,
                        json.len()
                    );
                }
                json.len() as i32
            } else {
                -1 // Buffer too small
            }
        } else {
            0 // No events
        }
    })
}
```

## Phase 3: Flutter Integration

### Week 5: Dart FFI Setup

#### 5.1 FFI Bindings
```dart
// lib/src/ffi/bindings.dart
import 'dart:ffi';
import 'dart:typed_data';

class ZedBindings {
  late final DynamicLibrary _lib;

  // Function pointers
  late final int Function() _init;
  late final Pointer<Utf8> Function() _createThread;
  late final int Function(Pointer<Uint8>, int) _pollEvents;

  ZedBindings() {
    _lib = _loadLibrary();
    _init = _lib.lookup<NativeFunction<Int32 Function()>>('zed_mobile_init')
        .asFunction();
    _createThread = _lib.lookup<NativeFunction<Pointer<Utf8> Function()>>('zed_mobile_create_thread')
        .asFunction();
    _pollEvents = _lib.lookup<NativeFunction<Int32 Function(Pointer<Uint8>, Uint32)>>('zed_mobile_poll_events')
        .asFunction();
  }
}
```

#### 5.2 Event Stream Handler
```dart
// lib/src/ffi/event_stream.dart
class EventStreamHandler {
  final ZedBindings _bindings;
  final _eventController = StreamController<AgentEvent>.broadcast();
  Timer? _pollTimer;
  final _buffer = Uint8List(4096);

  Stream<AgentEvent> get events => _eventController.stream;

  void startPolling() {
    _pollTimer = Timer.periodic(Duration(milliseconds: 16), (_) {
      final ptr = _buffer.buffer.asUint8List().cast<Uint8>().address;
      final size = _bindings._pollEvents(Pointer<Uint8>.fromAddress(ptr), _buffer.length);

      if (size > 0) {
        final json = utf8.decode(_buffer.sublist(0, size));
        final event = AgentEvent.fromJson(jsonDecode(json));
        _eventController.add(event);
      }
    });
  }
}
```

### Week 6: Core UI Components

#### 6.1 Message Widget
```dart
// lib/src/ui/widgets/message_widget.dart
class MessageWidget extends StatelessWidget {
  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) AvatarWidget(role: message.role),
          Expanded(
            child: Card(
              color: message.isUser
                ? Theme.of(context).primaryColor.withOpacity(0.1)
                : Theme.of(context).cardColor,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: _buildContent(),
              ),
            ),
          ),
          if (message.isUser) AvatarWidget(role: message.role),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (message.content.type == ContentType.text) {
      return MarkdownBody(data: message.content.text);
    } else if (message.content.type == ContentType.toolCall) {
      return ToolCallWidget(toolCall: message.content.toolCall);
    }
    return Text('Unknown content type');
  }
}
```

## Phase 4: Network Communication

### Week 7: Zed Extension

#### 7.1 Extension Structure
```toml
# zed-extension/extension.toml
id = "zed-mobile-bridge"
name = "Zed Mobile Bridge"
version = "0.1.0"
schema_version = 1

[capabilities]
websocket_server = true
agent_panel_access = true
```

#### 7.2 WebSocket Server
```rust
// zed-extension/src/server.rs
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;

pub struct MobileBridgeServer {
    agent_panel: WeakEntity<AgentPanel>,
    clients: Arc<Mutex<HashMap<Uuid, Client>>>,
}

impl MobileBridgeServer {
    pub async fn start(&self, addr: &str) -> Result<()> {
        let listener = TcpListener::bind(addr).await?;

        while let Ok((stream, addr)) = listener.accept().await {
            let ws_stream = accept_async(stream).await?;
            self.handle_client(ws_stream).await;
        }

        Ok(())
    }

    async fn broadcast_update(&self, update: AgentUpdate) {
        let clients = self.clients.lock().await;
        let msg = Message::text(serde_json::to_string(&update).unwrap());

        for (_, client) in clients.iter() {
            client.send(msg.clone()).await.ok();
        }
    }
}
```

### Week 8: Mobile Network Client

#### 8.1 WebSocket Client
```dart
// lib/src/network/websocket_client.dart
class ZedWebSocketClient {
  WebSocketChannel? _channel;
  final _reconnectTimer = RestartableTimer(Duration(seconds: 5), () {});

  Future<void> connect(String url) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // Send authentication
      _channel!.sink.add(jsonEncode({
        'type': 'auth',
        'token': await _getAuthToken(),
      }));
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    final update = AgentUpdate.fromJson(jsonDecode(message));
    _updateController.add(update);
  }
}
```

## Phase 5: Advanced Features

### Week 9: Voice Input

#### 9.1 Voice Recognition Service
```dart
// lib/src/services/voice_service.dart
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;

  Future<void> initialize() async {
    final available = await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );

    if (!available) {
      throw Exception('Speech recognition not available');
    }
  }

  Stream<String> startListening() async* {
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          yield result.recognizedWords;
        }
      },
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }
}
```

### Week 10: Offline Support

#### 10.1 Local Database
```dart
// lib/src/storage/database.dart
class LocalDatabase {
  late final Database _db;

  Future<void> initialize() async {
    final path = await getDatabasesPath();
    _db = await openDatabase(
      join(path, 'zed_mobile.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        summary TEXT,
        messages TEXT,
        updated_at INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        thread_id TEXT,
        content TEXT,
        created_at INTEGER
      )
    ''');
  }
}
```

## Testing Strategy

### Unit Tests
```dart
// test/ffi/bridge_test.dart
void main() {
  group('FFI Bridge', () {
    test('initializes successfully', () async {
      final bridge = ZedMobileBridge();
      expect(() => bridge.initialize(), completes);
    });

    test('creates thread', () async {
      final bridge = ZedMobileBridge();
      await bridge.initialize();

      final threadId = await bridge.createThread();
      expect(threadId, isNotEmpty);
    });
  });
}
```

### Integration Tests
```dart
// integration_test/app_test.dart
void main() {
  testWidgets('Send message flow', (tester) async {
    await tester.pumpWidget(MyApp());

    // Type message
    await tester.enterText(find.byType(TextField), 'Hello, Zed!');

    // Send message
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // Verify message appears
    expect(find.text('Hello, Zed!'), findsOneWidget);
  });
}
```

## Performance Targets

- App launch: < 2 seconds
- Message send latency: < 100ms
- Memory usage: < 50MB baseline
- Battery impact: < 5% over 1 hour
- Network bandwidth: < 10KB/s average

## Deployment Pipeline

### CI/CD Setup
```yaml
# .github/workflows/mobile.yml
name: Mobile Build
on: [push, pull_request]

jobs:
  build-rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Bridge
        run: |
          cd bridge
          cargo build --release

  build-flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - name: Build APK
        run: |
          cd mobile
          flutter build apk --release
```

This technical roadmap provides concrete implementation details for each phase of development, ensuring a clear path from concept to production-ready mobile app.
