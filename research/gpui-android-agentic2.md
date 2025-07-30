# GPUI-less Android Implementation for Zed Mobile Agentic UI
# GPUI-less Flutter Implementation for Zed Mobile Agentic UI

## Overview

GPUI is Zed's custom GPU-accelerated UI framework that currently only supports desktop platforms (macOS, Windows, Linux). For Android, we need to extract Zed's agent data structures and business logic while reimplementing the UI using Android-native frameworks.
GPUI is Zed's custom GPU-accelerated UI framework that currently only supports desktop platforms (macOS, Windows, Linux). For mobile, we need to extract Zed's agent data structures and business logic while reimplementing the UI using Flutter.

## Why GPUI Won't Work on Mobile

```
┌─────────────────────────────────────┐
│      Android UI (Jetpack Compose)   │
│        Flutter UI (Widgets)         │
├─────────────────────────────────────┤
│         Kotlin ViewModels           │
│     Flutter State Management        │
│        (Riverpod/Bloc)             │
├─────────────────────────────────────┤
│      JNI/FFI Bridge Layer          │
│      Dart FFI Bridge Layer         │
├─────────────────────────────────────┤
│    Rust Business Logic (No GPUI)   │
├─────────────────────────────────────┤
use agent::{Thread, ThreadStore, Message};
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;

pub struct AgentManager {
    thread_store: Arc<ThreadStore>,
    active_thread: Arc<Mutex<Option<Thread>>>,
    event_tx: broadcast::Sender<AgentEvent>,
    // No Entity<T> or Context<T> from GPUI
}

impl AgentManager {
    pub fn new() -> Self {
        // Initialize without GPUI context
        let (event_tx, _) = broadcast::channel(1024);
        Self {
            thread_store: Arc::new(ThreadStore::new_headless()),
            active_thread: Arc::new(Mutex::new(None)),
            event_tx,
        }
    }
    
        let thread = self.thread_store.create_thread_headless()?;
        let thread_id = thread.id().clone();
        
        // Emit event for Flutter
        self.event_tx.send(AgentEvent::ThreadCreated(thread_id.clone())).ok();
        
        *self.active_thread.lock().unwrap() = Some(thread);
        Ok(thread_id)
    }
        let mut thread_guard = self.active_thread.lock().unwrap();
        if let Some(thread) = thread_guard.as_mut() {
            thread.send_message_headless(content)
            let message_id = thread.send_message_headless(content)?;
            self.event_tx.send(AgentEvent::MessageAdded(thread.id().clone(), message_id)).ok();
            Ok(message_id)
        } else {
            Err(Error::NoActiveThread)
        }
    }
    
    pub fn subscribe_events(&self) -> broadcast::Receiver<AgentEvent> {
        self.event_tx.subscribe()
    }
}
```

    AssistantResponse(ThreadId, String),
    ToolCallRequested(ThreadId, ToolCall),
    StreamingContent(ThreadId, String),
    Error(String),
}

pub struct EventStream {
    tx: broadcast::Sender<AgentEvent>,
    manager: Arc<AgentManager>,
    rx: broadcast::Receiver<AgentEvent>,
}

impl EventStream {
    pub fn new() -> Self {
        let (tx, rx) = broadcast::channel(1024);
        Self { tx, rx }
    pub fn new(manager: Arc<AgentManager>) -> Self {
        let rx = manager.subscribe_events();
        Self { manager, rx }
    }
    
    pub fn subscribe(&self) -> broadcast::Receiver<AgentEvent> {
        self.tx.subscribe()
    pub async fn next_event(&mut self) -> Option<AgentEvent> {
        self.rx.recv().await.ok()
    }
}
```

## Android Implementation
## Flutter Implementation

### 1. Kotlin Data Models
### 1. Dart FFI Models

```kotlin
// Mirror Rust structures in Kotlin
data class Thread(
    val id: String,
    val summary: String,
    val messages: List<Message>,
    val tokenUsage: TokenUsage
)
```dart
// lib/ffi/models.dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

data class Message(
    val id: Long,
    val role: MessageRole,
    val content: String,
    val timestamp: Long
)
// FFI-safe structures
class FfiThread extends Struct {
  external Pointer<Utf8> id;
  external Pointer<Utf8> summary;
  @Uint32()
  external int messageCount;
  @Int64()
  external int updatedAt;
}

enum class MessageRole {
    USER, ASSISTANT, SYSTEM
class FfiMessage extends Struct {
  @Uint32()
  external int id;
  @Uint8()
  external int role; // 0=User, 1=Assistant, 2=System
  external Pointer<Utf8> content;
  @Int64()
  external int timestamp;
}

data class ToolCall(
    val id: String,
    val name: String,
    val status: ToolCallStatus,
    val parameters: Map<String, Any>
)
class FfiToolCall extends Struct {
  external Pointer<Utf8> id;
  external Pointer<Utf8> name;
  @Uint8()
  external int status;
  external Pointer<Utf8> parameters; // JSON string
}

// Dart models
class Thread {
  final String id;
  final String summary;
  final List<Message> messages;
  final TokenUsage tokenUsage;
  
  Thread({
    required this.id,
    required this.summary,
    required this.messages,
    required this.tokenUsage,
  });
}

class Message {
  final int id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ToolCall>? toolCalls;
  
  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls,
  });
}

enum MessageRole { user, assistant, system }
```

### 2. JNI Bridge
### 2. Flutter FFI Bridge

```dart
// lib/ffi/bridge.dart
import 'dart:ffi';
import 'dart:async';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'models.dart';

typedef InitializeNative = Bool Function();
typedef Initialize = bool Function();

typedef CreateThreadNative = Pointer<Utf8> Function();
typedef CreateThread = Pointer<Utf8> Function();

typedef SendMessageNative = Int64 Function(Pointer<Utf8> content);
typedef SendMessage = int Function(Pointer<Utf8> content);

typedef PollEventNative = Pointer<Utf8> Function();
typedef PollEvent = Pointer<Utf8> Function();

```kotlin
// Kotlin JNI interface
class ZedAgentBridge {
    companion object {
        init {
            System.loadLibrary("zed_agent_bridge")
        }
  late final DynamicLibrary _lib;
  late final Initialize _initialize;
  late final CreateThread _createThread;
  late final SendMessage _sendMessage;
  late final PollEvent _pollEvent;
  
  final _eventController = StreamController<AgentEvent>.broadcast();
  Stream<AgentEvent> get events => _eventController.stream;
  
  Timer? _pollTimer;
  
  ZedAgentBridge() {
    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libzed_mobile_bridge.so')
        : DynamicLibrary.open('zed_mobile_bridge.framework/zed_mobile_bridge');
    
    _initialize = _lib
        .lookup<NativeFunction<InitializeNative>>('zed_agent_initialize')
        .asFunction();
    
    _createThread = _lib
        .lookup<NativeFunction<CreateThreadNative>>('zed_agent_create_thread')
        .asFunction();
    
    _sendMessage = _lib
        .lookup<NativeFunction<SendMessageNative>>('zed_agent_send_message')
        .asFunction();
    
    _pollEvent = _lib
        .lookup<NativeFunction<PollEventNative>>('zed_agent_poll_event')
        .asFunction();
  }
  
  Future<void> initialize() async {
    if (!_initialize()) {
      throw Exception('Failed to initialize Zed agent');
    }
    
    external fun initializeAgent(): Boolean
    external fun createThread(): String?
    external fun sendMessage(threadId: String, content: String): Long
    external fun getMessages(threadId: String): Array<Message>
    external fun subscribeToEvents(): Long // Returns event stream handle
    external fun pollEvent(handle: Long): AgentEvent?
    // Start event polling
    _pollTimer = Timer.periodic(Duration(milliseconds: 50), (_) {
      _pollForEvents();
    });
  }
  
  void _pollForEvents() {
    final eventPtr = _pollEvent();
    if (eventPtr.address != 0) {
      final eventJson = eventPtr.toDartString();
      calloc.free(eventPtr);
      
      final event = AgentEvent.fromJson(jsonDecode(eventJson));
      _eventController.add(event);
    }
  }
  
  Future<String> createThread() async {
    final threadIdPtr = _createThread();
    final threadId = threadIdPtr.toDartString();
    calloc.free(threadIdPtr);
    return threadId;
  }
  
  Future<int> sendMessage(String content) async {
    final contentPtr = content.toNativeUtf8();
    final messageId = _sendMessage(contentPtr);
    calloc.free(contentPtr);
    
    if (messageId < 0) {
      throw Exception('Failed to send message');
    }
    
    return messageId;
  }
  
  void dispose() {
    _pollTimer?.cancel();
    _eventController.close();
  }
}
```

### 3. Jetpack Compose UI
### 3. Flutter UI Components

```dart
// lib/ui/agent_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

```kotlin
// Compose UI implementation
@Composable
fun AgentPanel(
    viewModel: AgentViewModel = viewModel()
) {
    val threadState by viewModel.threadState.collectAsState()
    val messages by viewModel.messages.collectAsState()
class AgentPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(currentThreadProvider);
    final messages = ref.watch(messagesProvider);
    
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
    return Column(
      children: [
        // Thread header
        ThreadHeader(
            thread = threadState.currentThread,
            onNewThread = { viewModel.createNewThread() }
        )
        _ThreadHeader(thread: thread),
        
        // Message list
        LazyColumn(
            modifier = Modifier.weight(1f),
            reverseLayout = true
        ) {
            items(messages) { message ->
                MessageItem(
                    message = message,
                    onToolCallAction = { toolCall, action ->
                        viewModel.handleToolCallAction(toolCall, action)
                    }
                )
            }
        }
        // Messages list
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[messages.length - 1 - index];
              return _MessageItem(message: message);
            },
          ),
        ),
        
        // Input area
        MessageInput(
            onSendMessage = { content ->
                viewModel.sendMessage(content)
            }
        )
    }
        _MessageInput(),
      ],
    );
  }
}

@Composable
fun MessageItem(
    message: Message,
    onToolCallAction: (ToolCall, ToolCallAction) -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
class _MessageItem extends ConsumerWidget {
  final Message message;
  
  const _MessageItem({required this.message});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.all(8),
        padding: EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser 
            ? Theme.of(context).primaryColor.withOpacity(0.1)
            : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Role indicator
            Text(
                text = message.role.name,
                style = MaterialTheme.typography.caption,
                color = when (message.role) {
                    MessageRole.USER -> MaterialTheme.colors.primary
                    MessageRole.ASSISTANT -> MaterialTheme.colors.secondary
                    MessageRole.SYSTEM -> MaterialTheme.colors.onSurface.copy(alpha = 0.6f)
                }
            )
              message.role.name.toUpperCase(),
              style: Theme.of(context).textTheme.caption,
            ),
            SizedBox(height: 4),
            
            // Message content
            when (val content = message.content) {
                is TextContent -> {
                    Text(
                        text = content.text,
                        style = MaterialTheme.typography.body1
                    )
                }
                is CodeContent -> {
                    CodeBlock(
                        code = content.code,
                        language = content.language
                    )
                }
                is ToolCallContent -> {
                    ToolCallCard(
                        toolCall = content.toolCall,
                        onAction = onToolCallAction
                    )
                }
            }
        }
            if (message.content.contains('```'))
              _CodeBlockMessage(content: message.content)
            else
              MarkdownBody(data: message.content),
            
            // Tool calls
            if (message.toolCalls != null)
              ...(message.toolCalls!.map((call) => 
                _ToolCallCard(toolCall: call)
              )),
          ],
        ),
      ),
    );
  }
}

class _ToolCallCard extends ConsumerWidget {
  final ToolCall toolCall;
  
  const _ToolCallCard({required this.toolCall});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.only(top: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, size: 16),
                SizedBox(width: 8),
                Text(
                  toolCall.name,
                  style: Theme.of(context).textTheme.subtitle2,
                ),
                Spacer(),
                _ToolCallStatusChip(status: toolCall.status),
              ],
            ),
            if (toolCall.status == ToolCallStatus.waitingForConfirmation)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => ref.read(agentProvider.notifier)
                        .rejectToolCall(toolCall.id),
                    child: Text('Reject'),
                  ),
                  ElevatedButton(
                    onPressed: () => ref.read(agentProvider.notifier)
                        .approveToolCall(toolCall.id),
                    child: Text('Approve'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageInput extends ConsumerStatefulWidget {
  @override
  _MessageInputState createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<_MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
  
  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ref.read(agentProvider.notifier).sendMessage(text);
      _controller.clear();
      _focusNode.requestFocus();
    }
  }
}
```

### 4. ViewModel with Coroutines
### 4. State Management with Riverpod

```dart
// lib/providers/agent_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/bridge.dart';

final agentBridgeProvider = Provider<ZedAgentBridge>((ref) {
  final bridge = ZedAgentBridge();
  ref.onDispose(() => bridge.dispose());
  return bridge;
});

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  final bridge = ref.watch(agentBridgeProvider);
  return AgentNotifier(bridge);
});

final currentThreadProvider = Provider<Thread?>((ref) {
  return ref.watch(agentProvider).currentThread;
});

final messagesProvider = Provider<List<Message>>((ref) {
  return ref.watch(agentProvider).messages;
});

class AgentState {
  final Thread? currentThread;
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  
  AgentState({
    this.currentThread,
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });
  
  AgentState copyWith({
    Thread? currentThread,
    List<Message>? messages,
    bool? isLoading,
    String? error,
  }) {
    return AgentState(
      currentThread: currentThread ?? this.currentThread,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

```kotlin
class AgentViewModel(
    private val bridge: ZedAgentBridge = ZedAgentBridge()
) : ViewModel() {
    private val _threadState = MutableStateFlow(ThreadState())
    val threadState: StateFlow<ThreadState> = _threadState.asStateFlow()
    
    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()
    
    private var eventStreamHandle: Long = 0
class AgentNotifier extends StateNotifier<AgentState> {
  final ZedAgentBridge _bridge;
  StreamSubscription? _eventSubscription;
  
  AgentNotifier(this._bridge) : super(AgentState()) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    
    init {
        initializeAgent()
        startEventPolling()
    try {
      await _bridge.initialize();
      
      // Subscribe to events
      _eventSubscription = _bridge.events.listen(_handleEvent);
      
      // Create initial thread
      await createNewThread();
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
    
    private fun initializeAgent() {
        viewModelScope.launch(Dispatchers.IO) {
            if (bridge.initializeAgent()) {
                createNewThread()
                eventStreamHandle = bridge.subscribeToEvents()
            }
        }
  }
  
  void _handleEvent(AgentEvent event) {
    switch (event.type) {
      case AgentEventType.messageAdded:
        _loadMessages();
        break;
      case AgentEventType.assistantResponse:
        _updateLastMessage(event.data);
        break;
      case AgentEventType.toolCallRequested:
        _addToolCall(event.data);
        break;
      case AgentEventType.error:
        state = state.copyWith(error: event.data);
        break;
    }
  }
  
  Future<void> createNewThread() async {
    final threadId = await _bridge.createThread();
    // Load thread details
    state = state.copyWith(
      currentThread: Thread(
        id: threadId,
        summary: 'New Thread',
        messages: [],
        tokenUsage: TokenUsage.empty(),
      ),
    );
  }
  
  Future<void> sendMessage(String content) async {
    // Add user message immediately
    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
    
    private fun startEventPolling() {
        viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                val event = bridge.pollEvent(eventStreamHandle)
                event?.let { handleEvent(it) }
                delay(50) // Poll every 50ms
            }
        }
    }
    state = state.copyWith(
      messages: [...state.messages, userMessage],
    );
    
    private suspend fun handleEvent(event: AgentEvent) {
        withContext(Dispatchers.Main) {
            when (event) {
                is AgentEvent.MessageAdded -> {
                    loadMessages()
                }
                is AgentEvent.AssistantResponse -> {
                    // Update UI with streaming response
                }
                is AgentEvent.ToolCallRequested -> {
                    // Show tool call UI
                }
            }
        }
    }
    
    fun sendMessage(content: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _threadState.value.currentThread?.let { thread ->
                bridge.sendMessage(thread.id, content)
            }
        }
    }
    // Send to backend
    await _bridge.sendMessage(content);
  }
  
  Future<void> approveToolCall(String toolCallId) async {
    await _bridge.approveToolCall(toolCallId);
  }
  
  Future<void> rejectToolCall(String toolCallId) async {
    await _bridge.rejectToolCall(toolCallId);
  }
  
  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
```


```rust
// src/ffi/android.rs
use jni::JNIEnv;
use jni::objects::{JClass, JString, JObject};
use jni::sys::{jlong, jboolean, jobjectArray};
// src/ffi/flutter.rs
use std::ffi::{CString, CStr};
use std::os::raw::c_char;
use std::sync::Arc;
use once_cell::sync::OnceCell;

static AGENT_MANAGER: OnceCell<Arc<AgentManager>> = OnceCell::new();

#[no_mangle]
pub extern "system" fn Java_com_zedmobile_ZedAgentBridge_initializeAgent(
    env: JNIEnv,
    _: JClass,
) -> jboolean {
    match initialize_agent() {
        Ok(_) => JNI_TRUE,
        Err(_) => JNI_FALSE,
pub extern "C" fn zed_agent_initialize() -> bool {
    match AgentManager::new() {
        Ok(manager) => {
            AGENT_MANAGER.set(Arc::new(manager)).is_ok()
        }
        Err(_) => false,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_zedmobile_ZedAgentBridge_sendMessage(
    env: JNIEnv,
    _: JClass,
    thread_id: JString,
    content: JString,
) -> jlong {
    let thread_id: String = env.get_string(thread_id).unwrap().into();
    let content: String = env.get_string(content).unwrap().into();
pub extern "C" fn zed_agent_create_thread() -> *mut c_char {
    let manager = match AGENT_MANAGER.get() {
        Some(m) => m,
        None => return std::ptr::null_mut(),
    };
    
    match send_message(&thread_id, &content) {
        Ok(message_id) => message_id.0 as jlong,
    match manager.create_thread() {
        Ok(thread_id) => {
            CString::new(thread_id.to_string())
                .unwrap()
                .into_raw()
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn zed_agent_send_message(content: *const c_char) -> i64 {
    let manager = match AGENT_MANAGER.get() {
        Some(m) => m,
        None => return -1,
    };
    
    let content = unsafe {
        match CStr::from_ptr(content).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };
    
    match manager.send_message(content) {
        Ok(message_id) => message_id.0 as i64,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn zed_agent_poll_event() -> *mut c_char {
    let manager = match AGENT_MANAGER.get() {
        Some(m) => m,
        None => return std::ptr::null_mut(),
    };
    
    // Non-blocking event poll
    match manager.poll_event() {
        Some(event) => {
            let json = serde_json::to_string(&event).unwrap();
            CString::new(json).unwrap().into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn zed_agent_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}
```

## Feature Parity Checklist
### UI Features to Reimplement
- [ ] Message formatting (Markdown, code blocks)
- [ ] Syntax highlighting
- [ ] Syntax highlighting for code
- [ ] Tool call confirmation UI
- [ ] Context picker
- [ ] Thread history
- Implement pagination for long threads
- Clear old threads from memory
- Use Android's lifecycle-aware components
- Use Flutter's built-in lifecycle management

### Battery Optimization
- Batch network requests
- Use WorkManager for background sync
- Implement adaptive polling rates
- Respect Doze mode
- Batch FFI calls
- Use adaptive polling rates
- Implement background task management
- Respect platform power saving modes

## Testing Strategy

### Unit Tests
- Test Rust business logic without UI
- Test JNI bridge functions
- Test Kotlin ViewModels

### UI Tests
- Compose UI tests
- Screenshot tests for different states
- Accessibility tests
- Test FFI bridge functions
- Test Dart models and serialization

### Widget Tests
```dart
testWidgets('AgentPanel displays messages', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: AgentPanel(),
      ),
    ),
  );
  
  // Test message display
  expect(find.text('USER'), findsOneWidget);
  expect(find.byType(MessageItem), findsNWidgets(2));
});
```

### Integration Tests
- End-to-end message flow

1. **Phase 1**: Extract core agent logic from GPUI dependencies
2. **Phase 2**: Implement minimal JNI bridge
3. **Phase 3**: Build basic Compose UI
2. **Phase 2**: Implement minimal FFI bridge
3. **Phase 3**: Build basic Flutter UI
4. **Phase 4**: Add advanced features (tool calls, context)
5. **Phase 5**: Optimize for mobile (offline, battery)

This approach allows us to leverage Zed's powerful agent architecture while providing a native Android experience optimized for mobile devices.
This approach allows us to leverage Zed's powerful agent architecture while providing a native mobile experience through Flutter that works seamlessly on both iOS and Android.