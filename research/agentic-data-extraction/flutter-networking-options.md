# Flutter Networking Options for Zed Mobile

## Overview

This document analyzes networking options for Flutter to communicate with Zed's agentic panel, focusing on real-time event streaming, state management, and compatibility with Rust/Tokio backend.

## 1. WebSocket Options

### web_socket_channel (Recommended)
The official WebSocket package for Flutter with excellent platform support.

```yaml
dependencies:
  web_socket_channel: ^2.4.0
```

**Implementation Example:**
```dart
import 'package:web_socket_channel/web_socket_channel.dart';

class ZedWebSocketClient {
  late WebSocketChannel _channel;
  final String _url;
  
  ZedWebSocketClient({required String host, required int port})
      : _url = 'ws://$host:$port/agent';
  
  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(_url));
    
    _channel.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) => _handleError(error),
      onDone: () => _handleDisconnect(),
    );
  }
  
  void sendEvent(AgentEvent event) {
    _channel.sink.add(jsonEncode(event.toJson()));
  }
}
```

### socket_io_client
For Socket.IO compatibility if needed.

```yaml
dependencies:
  socket_io_client: ^2.0.3
```

**Pros:**
- Auto-reconnection
- Event namespacing
- Room support

**Cons:**
- Overhead if not using Socket.IO features
- Larger bundle size

## 2. HTTP/REST Options

### dio (Recommended for HTTP)
Powerful HTTP client with interceptors, global configuration, and FormData.

```yaml
dependencies:
  dio: ^5.4.0
```

**Features:**
- Request/Response interceptors
- Global configuration
- File downloading/uploading
- Timeout and cancellation
- Certificate pinning

**Example with Interceptors:**
```dart
class ZedApiClient {
  late Dio _dio;
  
  ZedApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:8080',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 3),
    ));
    
    _dio.interceptors.add(AuthInterceptor());
    _dio.interceptors.add(LogInterceptor());
  }
  
  Future<List<Thread>> getThreads() async {
    final response = await _dio.get('/threads');
    return (response.data as List)
        .map((json) => Thread.fromJson(json))
        .toList();
  }
}
```

### http
Simple, lightweight HTTP client.

```yaml
dependencies:
  http: ^1.1.0
```

**Best for:**
- Simple REST calls
- Minimal dependencies
- Quick prototypes

## 3. Server-Sent Events (SSE)

### flutter_client_sse
For one-way real-time communication from server.

```yaml
dependencies:
  flutter_client_sse: ^2.0.1
```

**Example:**
```dart
class ZedEventStream {
  void subscribeToEvents() {
    SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: 'http://localhost:8080/events',
      header: {
        'Authorization': 'Bearer $token',
      },
    ).listen((event) {
      final agentEvent = AgentEvent.fromJson(jsonDecode(event.data!));
      _handleEvent(agentEvent);
    });
  }
}
```

## 4. gRPC Options

### grpc
Official gRPC package for Flutter.

```yaml
dependencies:
  grpc: ^3.2.4
  protobuf: ^3.1.0
```

**Pros:**
- Type-safe communication
- Efficient binary protocol
- Bidirectional streaming
- Built-in retry logic

**Example:**
```dart
class ZedGrpcClient {
  late ClientChannel channel;
  late AgentServiceClient stub;
  
  ZedGrpcClient() {
    channel = ClientChannel(
      'localhost',
      port: 50051,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    stub = AgentServiceClient(channel);
  }
  
  Stream<AgentEvent> subscribeToEvents() {
    final request = SubscribeRequest();
    return stub.subscribeToEvents(request);
  }
}
```

## 5. State Management Integration

### Riverpod + WebSocket
Best for reactive, event-driven architecture.

```dart
// WebSocket provider
final webSocketProvider = Provider<ZedWebSocketClient>((ref) {
  final client = ZedWebSocketClient(host: 'localhost', port: 8080);
  ref.onDispose(() => client.disconnect());
  return client;
});

// Event stream provider
final agentEventStreamProvider = StreamProvider<AgentEvent>((ref) {
  final ws = ref.watch(webSocketProvider);
  return ws.eventStream;
});

// Thread state notifier
class ThreadNotifier extends StateNotifier<Map<String, Thread>> {
  final Ref ref;
  
  ThreadNotifier(this.ref) : super({}) {
    // Subscribe to events
    ref.listen(agentEventStreamProvider, (previous, next) {
      next.whenData((event) => _handleEvent(event));
    });
  }
  
  void _handleEvent(AgentEvent event) {
    switch (event) {
      case ThreadCreated(:final thread):
        state = {...state, thread.id: thread};
      case ThreadUpdated(:final threadId, :final changes):
        final thread = state[threadId];
        if (thread != null) {
          state = {...state, threadId: thread.copyWith(changes)};
        }
    }
  }
}

final threadProvider = StateNotifierProvider<ThreadNotifier, Map<String, Thread>>(
  (ref) => ThreadNotifier(ref),
);
```

### Bloc + WebSocket
For more structured state management.

```dart
class AgentBloc extends Bloc<AgentEvent, AgentState> {
  final ZedWebSocketClient _client;
  StreamSubscription? _eventSubscription;
  
  AgentBloc(this._client) : super(AgentInitial()) {
    on<ThreadCreated>(_onThreadCreated);
    on<MessageAdded>(_onMessageAdded);
    
    _eventSubscription = _client.eventStream.listen((event) {
      add(event);
    });
  }
  
  void _onThreadCreated(ThreadCreated event, Emitter<AgentState> emit) {
    final currentState = state;
    if (currentState is AgentLoaded) {
      emit(currentState.copyWith(
        threads: [...currentState.threads, event.thread],
      ));
    }
  }
}
```

## 6. Offline Support & Caching

### drift + connectivity_plus
For offline-first architecture.

```yaml
dependencies:
  drift: ^2.14.0
  connectivity_plus: ^5.0.2
  
dev_dependencies:
  drift_dev: ^2.14.0
```

**Example:**
```dart
@DataClassName('CachedThread')
class CachedThreads extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get data => text()(); // JSON
  DateTimeColumn get updatedAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class OfflineSync {
  final AppDatabase db;
  final ZedWebSocketClient client;
  
  Stream<List<Thread>> watchThreads() {
    return Connectivity().onConnectivityChanged.switchMap((result) {
      if (result != ConnectivityResult.none) {
        // Online: fetch from server
        return _fetchAndCacheThreads();
      } else {
        // Offline: return cached data
        return db.watchAllThreads();
      }
    });
  }
}
```

## 7. Security Considerations

### flutter_secure_storage
For storing authentication tokens.

```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

**Example:**
```dart
class AuthStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'zed_auth_token';
  
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }
  
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }
}
```

### Certificate Pinning with dio
```dart
(_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
  final client = HttpClient();
  client.badCertificateCallback = (cert, host, port) {
    // Verify certificate fingerprint
    return cert.sha256 == expectedFingerprint;
  };
  return client;
};
```

## 8. Testing

### Mock WebSocket for Testing
```dart
class MockWebSocketChannel implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  
  @override
  Stream get stream => _controller.stream;
  
  @override
  WebSocketSink get sink => MockWebSocketSink(_controller);
  
  void simulateMessage(String message) {
    _controller.add(message);
  }
}

// In tests
test('handles thread created event', () async {
  final mockChannel = MockWebSocketChannel();
  final client = ZedWebSocketClient.withChannel(mockChannel);
  
  final thread = Thread(id: '123', title: 'Test Thread');
  mockChannel.simulateMessage(jsonEncode({
    'type': 'ThreadCreated',
    'data': {'thread': thread.toJson()},
  }));
  
  await expectLater(
    client.eventStream,
    emits(isA<ThreadCreated>().having((e) => e.thread.id, 'thread.id', '123')),
  );
});
```

## 9. Performance Optimization

### Message Batching
```dart
class BatchedEventProcessor {
  final _eventBuffer = <AgentEvent>[];
  Timer? _batchTimer;
  
  void addEvent(AgentEvent event) {
    _eventBuffer.add(event);
    _scheduleBatch();
  }
  
  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 50), () {
      if (_eventBuffer.isNotEmpty) {
        _processBatch(_eventBuffer.toList());
        _eventBuffer.clear();
      }
    });
  }
}
```

### Debouncing UI Updates
```dart
extension DebouncedStream<T> on Stream<T> {
  Stream<T> debounce(Duration duration) {
    return debounceTime(duration);
  }
}

// Usage
final debouncedMessages = messageStream
    .debounce(const Duration(milliseconds: 100));
```

## 10. Recommended Architecture

For Zed Mobile, the recommended stack is:

1. **Transport**: WebSocket (web_socket_channel)
   - Real-time bidirectional communication
   - Works well with Tokio backend
   - Good Flutter support

2. **State Management**: Riverpod
   - Reactive programming model
   - Good for event-driven architecture
   - Easy testing

3. **HTTP Client**: dio
   - For REST endpoints
   - File uploads/downloads
   - Interceptor support

4. **Serialization**: json_serializable + freezed
   - Type-safe JSON handling
   - Immutable data classes
   - Good IDE support

5. **Offline Support**: drift + connectivity_plus
   - SQLite for local storage
   - Automatic sync when online
   - Query builder

6. **Security**: flutter_secure_storage
   - Secure token storage
   - Platform-specific encryption

This combination provides a robust, scalable foundation for real-time communication between Flutter and Zed's Rust backend.