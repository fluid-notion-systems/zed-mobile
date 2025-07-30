# GPUI-less Android Implementation for Zed Mobile Agentic UI

## Overview

GPUI is Zed's custom GPU-accelerated UI framework that currently only supports desktop platforms (macOS, Windows, Linux). For Android, we need to extract Zed's agent data structures and business logic while reimplementing the UI using Android-native frameworks.

## Why GPUI Won't Work on Mobile

### Current Platform Support
- GPUI only has platform implementations for:
  - macOS (`platform/mac`)
  - Windows (`platform/windows`)
  - Linux (`platform/linux`)
- No mobile platform support (no `platform/android` or `platform/ios`)
- GPUI relies on desktop-specific windowing systems and GPU APIs

### Technical Barriers
1. **Window Management**: GPUI expects desktop window managers
2. **GPU Access**: Uses desktop GPU APIs (Metal, DirectX, Vulkan)
3. **Input Systems**: Built for mouse/keyboard, not touch
4. **Resource Management**: Desktop-oriented memory and threading models

## Architecture Strategy

### Layer Separation

```
┌─────────────────────────────────────┐
│      Android UI (Jetpack Compose)   │
├─────────────────────────────────────┤
│         Kotlin ViewModels           │
├─────────────────────────────────────┤
│      JNI/FFI Bridge Layer          │
├─────────────────────────────────────┤
│    Rust Business Logic (No GPUI)   │
├─────────────────────────────────────┤
│    Zed Agent Data Structures       │
└─────────────────────────────────────┘
```

## Extracting Agent Logic Without GPUI

### 1. Core Data Structures (GPUI-free)

These structures from the `agent` crate can be used directly:

```rust
// From agent crate - no GPUI dependencies
pub use agent::{
    Thread, ThreadId, ThreadSummary,
    Message, MessageId, MessageSegment,
    TokenUsage, ThreadError, ThreadEvent,
    context::{AgentContext, ContextId},
};
```

### 2. Creating GPUI-free Agent Manager

```rust
// src/agent_manager.rs - Custom implementation without GPUI
use agent::{Thread, ThreadStore, Message};
use std::sync::{Arc, Mutex};

pub struct AgentManager {
    thread_store: Arc<ThreadStore>,
    active_thread: Arc<Mutex<Option<Thread>>>,
    // No Entity<T> or Context<T> from GPUI
}

impl AgentManager {
    pub fn new() -> Self {
        // Initialize without GPUI context
        Self {
            thread_store: Arc::new(ThreadStore::new_headless()),
            active_thread: Arc::new(Mutex::new(None)),
        }
    }

    pub fn create_thread(&self) -> Result<ThreadId, Error> {
        // Thread creation without GPUI
        let thread = self.thread_store.create_thread_headless()?;
        let thread_id = thread.id().clone();
        *self.active_thread.lock().unwrap() = Some(thread);
        Ok(thread_id)
    }

    pub fn send_message(&self, content: String) -> Result<MessageId, Error> {
        // Message sending without GPUI updates
        let mut thread_guard = self.active_thread.lock().unwrap();
        if let Some(thread) = thread_guard.as_mut() {
            thread.send_message_headless(content)
        } else {
            Err(Error::NoActiveThread)
        }
    }
}
```

### 3. Event System Without GPUI

Replace GPUI's event system with a channel-based approach:

```rust
// src/event_stream.rs
use tokio::sync::broadcast;
use agent::{ThreadEvent, MessageId};

#[derive(Clone, Debug)]
pub enum AgentEvent {
    ThreadCreated(ThreadId),
    MessageAdded(ThreadId, MessageId),
    AssistantResponse(ThreadId, String),
    ToolCallRequested(ThreadId, ToolCall),
    Error(String),
}

pub struct EventStream {
    tx: broadcast::Sender<AgentEvent>,
    rx: broadcast::Receiver<AgentEvent>,
}

impl EventStream {
    pub fn new() -> Self {
        let (tx, rx) = broadcast::channel(1024);
        Self { tx, rx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<AgentEvent> {
        self.tx.subscribe()
    }
}
```

## Android Implementation

### 1. Kotlin Data Models

```kotlin
// Mirror Rust structures in Kotlin
data class Thread(
    val id: String,
    val summary: String,
    val messages: List<Message>,
    val tokenUsage: TokenUsage
)

data class Message(
    val id: Long,
    val role: MessageRole,
    val content: String,
    val timestamp: Long
)

enum class MessageRole {
    USER, ASSISTANT, SYSTEM
}

data class ToolCall(
    val id: String,
    val name: String,
    val status: ToolCallStatus,
    val parameters: Map<String, Any>
)
```

### 2. JNI Bridge

```kotlin
// Kotlin JNI interface
class ZedAgentBridge {
    companion object {
        init {
            System.loadLibrary("zed_agent_bridge")
        }
    }

    external fun initializeAgent(): Boolean
    external fun createThread(): String?
    external fun sendMessage(threadId: String, content: String): Long
    external fun getMessages(threadId: String): Array<Message>
    external fun subscribeToEvents(): Long // Returns event stream handle
    external fun pollEvent(handle: Long): AgentEvent?
}
```

### 3. Jetpack Compose UI

```kotlin
// Compose UI implementation
@Composable
fun AgentPanel(
    viewModel: AgentViewModel = viewModel()
) {
    val threadState by viewModel.threadState.collectAsState()
    val messages by viewModel.messages.collectAsState()

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Thread header
        ThreadHeader(
            thread = threadState.currentThread,
            onNewThread = { viewModel.createNewThread() }
        )

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

        // Input area
        MessageInput(
            onSendMessage = { content ->
                viewModel.sendMessage(content)
            }
        )
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
    }
}
```

### 4. ViewModel with Coroutines

```kotlin
class AgentViewModel(
    private val bridge: ZedAgentBridge = ZedAgentBridge()
) : ViewModel() {
    private val _threadState = MutableStateFlow(ThreadState())
    val threadState: StateFlow<ThreadState> = _threadState.asStateFlow()

    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()

    private var eventStreamHandle: Long = 0

    init {
        initializeAgent()
        startEventPolling()
    }

    private fun initializeAgent() {
        viewModelScope.launch(Dispatchers.IO) {
            if (bridge.initializeAgent()) {
                createNewThread()
                eventStreamHandle = bridge.subscribeToEvents()
            }
        }
    }

    private fun startEventPolling() {
        viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                val event = bridge.pollEvent(eventStreamHandle)
                event?.let { handleEvent(it) }
                delay(50) // Poll every 50ms
            }
        }
    }

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
}
```

## Rust FFI Implementation

```rust
// src/ffi/android.rs
use jni::JNIEnv;
use jni::objects::{JClass, JString, JObject};
use jni::sys::{jlong, jboolean, jobjectArray};

#[no_mangle]
pub extern "system" fn Java_com_zedmobile_ZedAgentBridge_initializeAgent(
    env: JNIEnv,
    _: JClass,
) -> jboolean {
    match initialize_agent() {
        Ok(_) => JNI_TRUE,
        Err(_) => JNI_FALSE,
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

    match send_message(&thread_id, &content) {
        Ok(message_id) => message_id.0 as jlong,
        Err(_) => -1,
    }
}
```

## Feature Parity Checklist

### Core Features
- [x] Thread management (create, delete, switch)
- [x] Message sending and receiving
- [x] Assistant streaming responses
- [x] Tool call handling
- [x] Context management
- [x] Token usage tracking

### UI Features to Reimplement
- [ ] Message formatting (Markdown, code blocks)
- [ ] Syntax highlighting
- [ ] Tool call confirmation UI
- [ ] Context picker
- [ ] Thread history
- [ ] Search functionality
- [ ] Voice input integration
- [ ] Diff visualization

### Mobile-Specific Features
- [ ] Touch-optimized interactions
- [ ] Swipe gestures (delete, reply)
- [ ] Offline mode with sync
- [ ] Push notifications
- [ ] Share functionality
- [ ] Dark/light theme support

## Performance Considerations

### Memory Management
- Use lazy loading for message history
- Implement pagination for long threads
- Clear old threads from memory
- Use Android's lifecycle-aware components

### Battery Optimization
- Batch network requests
- Use WorkManager for background sync
- Implement adaptive polling rates
- Respect Doze mode

## Testing Strategy

### Unit Tests
- Test Rust business logic without UI
- Test JNI bridge functions
- Test Kotlin ViewModels

### UI Tests
- Compose UI tests
- Screenshot tests for different states
- Accessibility tests

### Integration Tests
- End-to-end message flow
- Tool call execution
- Error handling scenarios

## Migration Path

1. **Phase 1**: Extract core agent logic from GPUI dependencies
2. **Phase 2**: Implement minimal JNI bridge
3. **Phase 3**: Build basic Compose UI
4. **Phase 4**: Add advanced features (tool calls, context)
5. **Phase 5**: Optimize for mobile (offline, battery)

This approach allows us to leverage Zed's powerful agent architecture while providing a native Android experience optimized for mobile devices.
