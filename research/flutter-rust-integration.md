# Flutter-Rust Integration & Direct GPUI Usage Research

## Overview

This document explores the possibility of deep Flutter-Rust integration for Zed Mobile, including the potential to use GPUI (Zed's UI framework) and the agentic panel components directly. This approach could provide native performance and seamless integration with Zed's core functionality.

## Flutter-Rust Integration Options

### 1. Flutter FFI (Foreign Function Interface)

Flutter's dart:ffi enables direct calling of native C APIs, which Rust can expose.

```dart
// Dart FFI binding
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Define Rust function signatures
typedef RustInitializeFunc = Void Function();
typedef DartInitializeFunc = void Function();

typedef RustGetAgentUpdatesFunc = Pointer<Utf8> Function();
typedef DartGetAgentUpdatesFunc = Pointer<Utf8> Function();

class ZedNativeBinding {
  late final DynamicLibrary _dylib;
  late final DartInitializeFunc initialize;
  late final DartGetAgentUpdatesFunc getAgentUpdates;

  ZedNativeBinding() {
    _dylib = Platform.isAndroid
        ? DynamicLibrary.open('libzed_mobile.so')
        : DynamicLibrary.open('zed_mobile.framework/zed_mobile');

    initialize = _dylib
        .lookup<NativeFunction<RustInitializeFunc>>('zed_initialize')
        .asFunction();

    getAgentUpdates = _dylib
        .lookup<NativeFunction<RustGetAgentUpdatesFunc>>('zed_get_agent_updates')
        .asFunction();
  }
}
```

```rust
// Rust FFI implementation
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn zed_initialize() {
    // Initialize GPUI and Zed components
    std::thread::spawn(|| {
        gpui::App::new().run(|cx| {
            // Initialize minimal Zed environment
            initialize_agent_panel(cx);
        });
    });
}

#[no_mangle]
pub extern "C" fn zed_get_agent_updates() -> *mut c_char {
    let updates = collect_agent_updates();
    let json = serde_json::to_string(&updates).unwrap();
    CString::new(json).unwrap().into_raw()
}
```

### 2. Flutter Rust Bridge

A code generator that creates type-safe bindings between Flutter and Rust.

```rust
// api.rs - Define the bridge API
use flutter_rust_bridge::frb;

#[frb]
pub struct AgentUpdate {
    pub session_id: String,
    pub content: String,
    pub timestamp: i64,
}

#[frb]
pub struct ZedMobileBridge {
    agent_panel: Arc<Mutex<AgentPanelHandle>>,
}

#[frb]
impl ZedMobileBridge {
    pub fn new() -> Self {
        Self {
            agent_panel: Arc::new(Mutex::new(AgentPanelHandle::new())),
        }
    }

    pub fn stream_agent_updates(&self) -> Stream<AgentUpdate> {
        let panel = self.agent_panel.clone();
        Stream::from_iter(async_stream::stream! {
            loop {
                let update = panel.lock().unwrap().next_update().await;
                yield update;
            }
        })
    }

    pub fn send_command(&self, command: String) -> Result<String> {
        self.agent_panel.lock().unwrap().execute_command(command)
    }
}
```

```dart
// Generated Dart code usage
import 'package:zed_mobile/bridge_generated.dart';

class AgentService {
  late final ZedMobileBridge _bridge;

  Future<void> initialize() async {
    _bridge = await ZedMobileBridge.new();

    // Listen to updates
    _bridge.streamAgentUpdates().listen((update) {
      print('Received: ${update.content}');
    });
  }

  Future<void> sendCommand(String command) async {
    final result = await _bridge.sendCommand(command);
    print('Command result: $result');
  }
}
```

## Direct GPUI Integration

### Understanding GPUI

GPUI is Zed's custom GPU-accelerated UI framework written in Rust. Key characteristics:

1. **Immediate Mode Rendering**: Efficient GPU-based rendering
2. **Entity Component System**: Reactive state management
3. **Platform Integration**: Native window and input handling
4. **Async Runtime**: Tokio-based async execution

### Embedding GPUI in Mobile

```rust
// mobile_gpui_host.rs - Host GPUI in mobile context
use gpui::{App, Context, ViewContext, Window};
use agent_ui::AgentPanel;

pub struct MobileGpuiHost {
    app: App,
    agent_panel: Option<Entity<AgentPanel>>,
}

impl MobileGpuiHost {
    pub fn new() -> Result<Self> {
        let app = App::new();
        Ok(Self {
            app,
            agent_panel: None,
        })
    }

    pub fn initialize_agent_panel(&mut self) -> Result<()> {
        self.app.run(|cx| {
            // Create a headless window for agent panel
            let window = cx.create_window(
                WindowOptions {
                    bounds: WindowBounds::Fixed(Bounds {
                        origin: Point::default(),
                        size: Size {
                            width: Pixels(360.0),
                            height: Pixels(640.0),
                        },
                    }),
                    is_headless: true, // Render to texture
                    ..Default::default()
                },
                |cx| {
                    // Initialize agent panel
                    let panel = AgentPanel::new(cx);
                    panel
                },
            );

            self.agent_panel = Some(window.root(cx));
        });

        Ok(())
    }

    pub fn render_to_texture(&mut self) -> Vec<u8> {
        self.app.run(|cx| {
            if let Some(panel) = &self.agent_panel {
                // Render GPUI to texture
                let texture = cx.render_entity_to_texture(panel);
                texture.to_rgba_bytes()
            } else {
                vec![]
            }
        })
    }
}
```

### Flutter Texture Rendering

```dart
// Display GPUI-rendered content in Flutter
class GpuiTextureWidget extends StatefulWidget {
  @override
  _GpuiTextureWidgetState createState() => _GpuiTextureWidgetState();
}

class _GpuiTextureWidgetState extends State<GpuiTextureWidget> {
  int? _textureId;
  final _nativeBinding = ZedNativeBinding();

  @override
  void initState() {
    super.initState();
    _initializeTexture();
  }

  Future<void> _initializeTexture() async {
    // Register texture with Flutter engine
    final textureId = await _nativeBinding.createGpuiTexture();
    setState(() {
      _textureId = textureId;
    });

    // Start rendering loop
    Timer.periodic(Duration(milliseconds: 16), (_) {
      _nativeBinding.updateGpuiTexture(textureId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return CircularProgressIndicator();
    }

    return Texture(textureId: _textureId!);
  }
}
```

## Direct Agent Panel Integration

### Approach 1: Headless Agent Panel

Extract and run agent panel logic without UI, exposing data through FFI.

```rust
// headless_agent_panel.rs
use acp_thread::{AcpThread, AgentThreadEntry};
use agent_client_protocol as acp;

pub struct HeadlessAgentPanel {
    thread: Arc<Mutex<AcpThread>>,
    update_tx: mpsc::Sender<AgentUpdate>,
}

impl HeadlessAgentPanel {
    pub fn new(project: Entity<Project>) -> (Self, mpsc::Receiver<AgentUpdate>) {
        let (tx, rx) = mpsc::channel(100);

        // Create ACP thread without UI
        let thread = AcpThread::new(
            connection,
            project,
            session_id,
            cx,
        );

        let panel = Self {
            thread: Arc::new(Mutex::new(thread)),
            update_tx: tx,
        };

        // Start monitoring thread
        panel.start_monitoring();

        (panel, rx)
    }

    fn start_monitoring(&self) {
        let thread = self.thread.clone();
        let tx = self.update_tx.clone();

        tokio::spawn(async move {
            loop {
                let entries = thread.lock().unwrap().entries().to_vec();

                for entry in entries {
                    let update = match entry {
                        AgentThreadEntry::UserMessage(msg) => {
                            AgentUpdate::UserMessage {
                                content: msg.to_markdown(),
                                timestamp: SystemTime::now(),
                            }
                        }
                        AgentThreadEntry::AssistantMessage(msg) => {
                            AgentUpdate::AssistantMessage {
                                content: msg.to_markdown(),
                                timestamp: SystemTime::now(),
                            }
                        }
                        AgentThreadEntry::ToolCall(call) => {
                            AgentUpdate::ToolCall {
                                id: call.id.clone(),
                                name: call.name.clone(),
                                status: call.status.clone(),
                            }
                        }
                    };

                    tx.send(update).await.ok();
                }

                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        });
    }
}
```

### Approach 2: Full GPUI Embedding

Run complete GPUI with agent panel, rendering to Flutter texture.

```rust
// full_gpui_embed.rs
pub struct EmbeddedZedRuntime {
    app: App,
    workspace: Entity<Workspace>,
    agent_panel: Entity<AgentPanel>,
    render_target: RenderTarget,
}

impl EmbeddedZedRuntime {
    pub fn new(surface_handle: RawWindowHandle) -> Result<Self> {
        let app = App::new();

        app.run(|cx| {
            // Initialize minimal Zed environment
            let workspace = create_headless_workspace(cx);
            let agent_panel = workspace.update(cx, |workspace, cx| {
                AgentPanel::new(workspace, cx)
            });

            // Create render target for mobile surface
            let render_target = RenderTarget::from_raw_handle(surface_handle);

            Ok(Self {
                app,
                workspace,
                agent_panel,
                render_target,
            })
        })
    }

    pub fn handle_input(&mut self, event: InputEvent) {
        self.app.run(|cx| {
            // Forward input events to GPUI
            match event {
                InputEvent::Touch(touch) => {
                    cx.dispatch_event(gpui::TouchEvent::from(touch));
                }
                InputEvent::Text(text) => {
                    cx.dispatch_event(gpui::InputEvent::from(text));
                }
                _ => {}
            }
        });
    }
}
```

## Platform-Specific Considerations

### iOS Integration

```swift
// iOS Native Module
@objc(ZedMobileBridge)
class ZedMobileBridge: NSObject {
    private var rustBridge: OpaquePointer?
    private var displayLink: CADisplayLink?

    @objc
    func initialize() {
        // Initialize Rust runtime
        rustBridge = zed_mobile_init()

        // Set up render loop
        displayLink = CADisplayLink(target: self, selector: #selector(render))
        displayLink?.add(to: .current, forMode: .default)
    }

    @objc
    private func render() {
        guard let bridge = rustBridge else { return }

        // Get rendered frame from GPUI
        let frameData = zed_mobile_render_frame(bridge)

        // Update Metal texture
        updateMetalTexture(frameData)
    }
}
```

### Android Integration

```kotlin
// Android Native Module
class ZedMobileBridge(private val context: Context) {
    private var rustBridge: Long = 0
    private lateinit var surfaceTexture: SurfaceTexture

    init {
        System.loadLibrary("zed_mobile")
    }

    fun initialize(surface: Surface) {
        rustBridge = nativeInit(surface)

        // Set up choreographer for vsync
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (rustBridge != 0L) {
                nativeRenderFrame(rustBridge)
                Choreographer.getInstance().postFrameCallback(this)
            }
        }
    }

    external fun nativeInit(surface: Surface): Long
    external fun nativeRenderFrame(handle: Long)
}
```

## Performance Analysis

### Memory Usage Comparison

| Approach | Base Memory | Per Session | Rendering |
|----------|------------|-------------|-----------|
| Flutter + REST API | 50MB | 5MB | Flutter |
| Flutter + FFI (Data) | 80MB | 8MB | Flutter |
| Flutter + GPUI Texture | 150MB | 12MB | GPUI |
| Full GPUI Embed | 200MB | 15MB | GPUI |

### Latency Comparison

| Operation | REST API | FFI | Direct GPUI |
|-----------|----------|-----|-------------|
| Update Display | 50-100ms | 5-10ms | 1-2ms |
| Send Command | 20-50ms | 2-5ms | <1ms |
| Voice Input | 100ms+ | 100ms+ | 100ms+ |

## Architectural Trade-offs

### Flutter + FFI (Data Only)

**Pros:**
- Minimal memory overhead
- Flutter handles all UI (familiar patterns)
- Easy to maintain Flutter-specific features
- Cross-platform UI consistency

**Cons:**
- Need to reimplement UI
- Potential data synchronization issues
- Limited access to Zed features

### Flutter + GPUI Rendering

**Pros:**
- Exact Zed UI appearance
- Access to all Zed UI features
- Native performance
- Reduced development time

**Cons:**
- Higher memory usage
- Complex platform integration
- Potential rendering synchronization issues
- Harder to add mobile-specific UI

### Recommendation

For Zed Mobile, I recommend a **hybrid approach**:

1. **Phase 1**: Flutter + FFI with data-only integration
   - Quick to implement
   - Lower complexity
   - Establish core functionality

2. **Phase 2**: Add GPUI rendering for agent panel view
   - Texture rendering for authentic Zed experience
   - Keep Flutter for mobile-specific UI (navigation, settings)

3. **Phase 3**: Evaluate full GPUI integration
   - Based on user feedback and performance requirements
   - Consider for tablet/desktop-class devices

## Implementation Roadmap

### Week 1-2: FFI Foundation
- Set up Rust library with basic FFI
- Implement headless agent panel extraction
- Create Flutter bindings

### Week 3-4: Data Synchronization
- Implement efficient data transfer
- Add incremental updates
- Handle connection lifecycle

### Week 5-6: GPUI Texture Rendering (Optional)
- Implement GPUI-to-texture rendering
- Integrate with Flutter texture widget
- Handle input forwarding

### Week 7-8: Platform Integration
- iOS Metal integration
- Android SurfaceTexture support
- Performance optimization

This approach provides the best balance of development speed, performance, and maintainability while keeping the door open for deeper integration in the future.
