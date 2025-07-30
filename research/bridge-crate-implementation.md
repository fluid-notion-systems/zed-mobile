# Zed Mobile Bridge Crate Implementation Plan

## Overview

The bridge crate serves as an intermediary between Zed's internal Rust crates and the mobile application. It provides FFI-safe interfaces, handles type conversions, and manages the lifecycle of Zed components in a mobile context.

## Project Structure

```
zed-mobile/
├── bridge/                      # Rust bridge crate
│   ├── Cargo.toml
│   ├── build.rs                # Build script for FFI generation
│   ├── src/
│   │   ├── lib.rs             # Main library entry point
│   │   ├── ffi/               # FFI-safe interfaces
│   │   │   ├── mod.rs
│   │   │   ├── types.rs       # FFI-safe type definitions
│   │   │   ├── thread.rs      # Thread-related FFI functions
│   │   │   └── panel.rs       # Panel-related FFI functions
│   │   ├── bridge/            # Bridge implementations
│   │   │   ├── mod.rs
│   │   │   ├── agent_panel.rs # AgentPanel bridge
│   │   │   ├── thread.rs      # Thread bridge
│   │   │   └── message.rs     # Message bridge
│   │   ├── runtime/           # Runtime management
│   │   │   ├── mod.rs
│   │   │   ├── gpui.rs        # GPUI runtime handling
│   │   │   └── executor.rs    # Async executor setup
│   │   └── utils/             # Utility functions
│   │       ├── mod.rs
│   │       ├── conversion.rs  # Type conversions
│   │       └── memory.rs      # Memory management
│   └── tests/
│       ├── integration.rs
│       └── ffi.rs
├── flutter_bridge/             # Dart FFI bindings (generated)
└── kotlin_bridge/             # Kotlin/JNI bindings (optional)
```

## Cargo.toml Configuration

```toml
[package]
name = "zed-mobile-bridge"
version = "0.1.0"
edition = "2021"

[lib]
name = "zed_mobile_bridge"
crate-type = ["cdylib", "staticlib"]

[dependencies]
# Core Zed dependencies
agent = { path = "../vendor/zed/crates/agent" }
agent_ui = { path = "../vendor/zed/crates/agent_ui" }
acp_thread = { path = "../vendor/zed/crates/acp_thread" }
gpui = { path = "../vendor/zed/crates/gpui" }
project = { path = "../vendor/zed/crates/project" }
language = { path = "../vendor/zed/crates/language" }
language_model = { path = "../vendor/zed/crates/language_model" }
agent_settings = { path = "../vendor/zed/crates/agent_settings" }
workspace = { path = "../vendor/zed/crates/workspace" }
fs = { path = "../vendor/zed/crates/fs" }

# External dependencies
anyhow = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["full"] }
futures = "0.3"
log = "0.4"
env_logger = "0.10"
once_cell = "1.19"
parking_lot = "0.12"

# FFI dependencies
ffi-support = "0.4"
uniffi = { version = "0.25", optional = true }

[build-dependencies]
cbindgen = "0.26"
uniffi = { version = "0.25", features = ["build"], optional = true }

[features]
default = ["flutter"]
flutter = []
kotlin = ["uniffi", "uniffi/build"]
ios = []
android = []

[profile.release]
lto = true
opt-level = 'z'
strip = true
```

## Core Bridge Implementation

### lib.rs - Main Entry Point

```rust
// src/lib.rs
#![allow(clippy::new_without_default)]

pub mod bridge;
pub mod ffi;
pub mod runtime;
pub mod utils;

use once_cell::sync::OnceCell;
use parking_lot::RwLock;
use std::sync::Arc;

// Global runtime instance
static RUNTIME: OnceCell<Arc<RwLock<ZedMobileRuntime>>> = OnceCell::new();

pub struct ZedMobileRuntime {
    gpui_runtime: runtime::GpuiRuntime,
    agent_panel: Option<bridge::AgentPanelBridge>,
    active_thread: Option<bridge::ThreadBridge>,
}

impl ZedMobileRuntime {
    pub fn initialize() -> Result<(), Box<dyn std::error::Error>> {
        env_logger::init();
        log::info!("Initializing Zed Mobile Runtime");

        let runtime = Arc::new(RwLock::new(Self {
            gpui_runtime: runtime::GpuiRuntime::new()?,
            agent_panel: None,
            active_thread: None,
        }));

        RUNTIME
            .set(runtime)
            .map_err(|_| "Runtime already initialized")?;

        Ok(())
    }

    pub fn get() -> Arc<RwLock<Self>> {
        RUNTIME.get().expect("Runtime not initialized").clone()
    }
}

// Re-export FFI functions
pub use ffi::*;
```

### FFI Type Definitions

```rust
// src/ffi/types.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// FFI-safe string
#[repr(C)]
pub struct FfiString {
    pub ptr: *const c_char,
    pub len: usize,
}

impl FfiString {
    pub fn from_str(s: &str) -> Self {
        let c_string = CString::new(s).unwrap_or_default();
        let len = c_string.as_bytes().len();
        Self {
            ptr: c_string.into_raw(),
            len,
        }
    }

    pub unsafe fn to_string(&self) -> String {
        if self.ptr.is_null() {
            return String::new();
        }
        let slice = std::slice::from_raw_parts(self.ptr as *const u8, self.len);
        String::from_utf8_lossy(slice).to_string()
    }
}

/// FFI-safe thread info
#[repr(C)]
pub struct FfiThreadInfo {
    pub id: FfiString,
    pub summary: FfiString,
    pub message_count: u32,
    pub updated_at: i64, // Unix timestamp
}

/// FFI-safe message
#[repr(C)]
pub struct FfiMessage {
    pub id: u32,
    pub role: FfiMessageRole,
    pub content: FfiString,
    pub timestamp: i64,
}

#[repr(C)]
pub enum FfiMessageRole {
    User = 0,
    Assistant = 1,
    System = 2,
}

/// FFI-safe tool call
#[repr(C)]
pub struct FfiToolCall {
    pub id: FfiString,
    pub name: FfiString,
    pub status: FfiToolCallStatus,
}

#[repr(C)]
pub enum FfiToolCallStatus {
    WaitingForConfirmation = 0,
    Allowed = 1,
    Rejected = 2,
    Canceled = 3,
}

/// Result types
#[repr(C)]
pub struct FfiResult<T> {
    pub success: bool,
    pub data: T,
    pub error: FfiString,
}
```

### Thread Bridge Implementation

```rust
// src/bridge/thread.rs
use agent::{Thread, ThreadId, Message, MessageRole};
use gpui::Entity;
use crate::ffi::types::*;

pub struct ThreadBridge {
    thread: Entity<Thread>,
    cached_messages: Vec<Message>,
}

impl ThreadBridge {
    pub fn new(thread: Entity<Thread>) -> Self {
        Self {
            thread,
            cached_messages: Vec::new(),
        }
    }

    pub fn get_info(&self, cx: &gpui::App) -> FfiThreadInfo {
        self.thread.read_in(cx, |thread, _| {
            FfiThreadInfo {
                id: FfiString::from_str(&thread.id().0),
                summary: FfiString::from_str(&thread.summary()),
                message_count: thread.messages().len() as u32,
                updated_at: thread.updated_at().timestamp(),
            }
        })
    }

    pub fn get_messages(&mut self, cx: &gpui::App) -> Vec<FfiMessage> {
        self.thread.read_in(cx, |thread, _| {
            thread.messages()
                .iter()
                .map(|msg| FfiMessage {
                    id: msg.id.0 as u32,
                    role: match msg.role {
                        MessageRole::User => FfiMessageRole::User,
                        MessageRole::Assistant => FfiMessageRole::Assistant,
                        MessageRole::System => FfiMessageRole::System,
                    },
                    content: FfiString::from_str(&msg.to_string()),
                    timestamp: 0, // Add timestamp if available
                })
                .collect()
        })
    }

    pub fn send_message(&self, content: &str, cx: &mut gpui::App) -> Result<(), String> {
        self.thread.update(cx, |thread, cx| {
            thread.send_message(content.to_string(), cx)
                .map_err(|e| e.to_string())
        })?
    }
}
```

### Agent Panel Bridge

```rust
// src/bridge/agent_panel.rs
use agent_ui::{AgentPanel, ActiveThread};
use gpui::{Entity, WeakEntity};
use workspace::Workspace;
use crate::bridge::ThreadBridge;

pub struct AgentPanelBridge {
    panel: WeakEntity<AgentPanel>,
    workspace: WeakEntity<Workspace>,
}

impl AgentPanelBridge {
    pub fn new(workspace: Entity<Workspace>, cx: &mut gpui::App) -> Result<Self, String> {
        let panel = workspace
            .read(cx)
            .panel::<AgentPanel>(cx)
            .ok_or("AgentPanel not found")?
            .downgrade();

        Ok(Self {
            panel,
            workspace: workspace.downgrade(),
        })
    }

    pub fn get_active_thread(&self, cx: &gpui::App) -> Option<ThreadBridge> {
        self.panel.upgrade()?.read_in(cx, |panel, cx| {
            panel.active_thread()
                .map(|thread| ThreadBridge::new(thread))
        })
    }

    pub fn create_new_thread(&self, cx: &mut gpui::App) -> Result<ThreadBridge, String> {
        let panel = self.panel.upgrade()
            .ok_or("Panel no longer exists")?;

        panel.update(cx, |panel, cx| {
            let thread = panel.new_thread(&Default::default(), cx);
            Ok(ThreadBridge::new(thread))
        })
    }
}
```

### GPUI Runtime Management

```rust
// src/runtime/gpui.rs
use gpui::{App, AsyncAppContext, Executor};
use std::thread;
use tokio::runtime::Runtime;

pub struct GpuiRuntime {
    app: App,
    executor: Executor,
    tokio_runtime: Runtime,
}

impl GpuiRuntime {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let app = App::new()?;
        let executor = app.executor();
        let tokio_runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()?;

        Ok(Self {
            app,
            executor,
            tokio_runtime,
        })
    }

    pub fn run_on_main<F, R>(&self, f: F) -> R
    where
        F: FnOnce(&mut App) -> R + Send + 'static,
        R: Send + 'static,
    {
        let (tx, rx) = std::sync::mpsc::channel();

        self.executor.spawn_on_main(move |cx| {
            let result = f(cx);
            tx.send(result).ok();
        });

        rx.recv().expect("Failed to receive from main thread")
    }
}
```

### FFI Functions

```rust
// src/ffi/mod.rs
mod types;
mod thread;
mod panel;

pub use types::*;

use crate::ZedMobileRuntime;
use std::ffi::CString;
use std::os::raw::c_char;

/// Initialize the Zed Mobile runtime
#[no_mangle]
pub extern "C" fn zed_mobile_init() -> FfiResult<bool> {
    match ZedMobileRuntime::initialize() {
        Ok(()) => FfiResult {
            success: true,
            data: true,
            error: FfiString::from_str(""),
        },
        Err(e) => FfiResult {
            success: false,
            data: false,
            error: FfiString::from_str(&e.to_string()),
        },
    }
}

/// Free a string allocated by Rust
#[no_mangle]
pub unsafe extern "C" fn zed_mobile_free_string(s: FfiString) {
    if !s.ptr.is_null() {
        let _ = CString::from_raw(s.ptr as *mut c_char);
    }
}

/// Get active thread info
#[no_mangle]
pub extern "C" fn zed_mobile_get_active_thread() -> FfiResult<FfiThreadInfo> {
    let runtime = ZedMobileRuntime::get();
    let runtime_guard = runtime.read();

    match &runtime_guard.active_thread {
        Some(thread) => {
            let info = runtime_guard.gpui_runtime.run_on_main(|cx| {
                thread.get_info(cx)
            });

            FfiResult {
                success: true,
                data: info,
                error: FfiString::from_str(""),
            }
        }
        None => FfiResult {
            success: false,
            data: FfiThreadInfo {
                id: FfiString::from_str(""),
                summary: FfiString::from_str(""),
                message_count: 0,
                updated_at: 0,
            },
            error: FfiString::from_str("No active thread"),
        },
    }
}

/// Send a message to the active thread
#[no_mangle]
pub extern "C" fn zed_mobile_send_message(content: FfiString) -> FfiResult<bool> {
    let runtime = ZedMobileRuntime::get();
    let runtime_guard = runtime.read();

    let content_str = unsafe { content.to_string() };

    match &runtime_guard.active_thread {
        Some(thread) => {
            let result = runtime_guard.gpui_runtime.run_on_main(|cx| {
                thread.send_message(&content_str, cx)
            });

            match result {
                Ok(()) => FfiResult {
                    success: true,
                    data: true,
                    error: FfiString::from_str(""),
                },
                Err(e) => FfiResult {
                    success: false,
                    data: false,
                    error: FfiString::from_str(&e),
                },
            }
        }
        None => FfiResult {
            success: false,
            data: false,
            error: FfiString::from_str("No active thread"),
        },
    }
}
```

### Build Script

```rust
// build.rs
use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let output_dir = env::var("OUT_DIR").unwrap();

    // Generate C headers using cbindgen
    let config = cbindgen::Config {
        language: cbindgen::Language::C,
        ..Default::default()
    };

    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_config(config)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(PathBuf::from(&output_dir).join("zed_mobile_bridge.h"));

    // Generate Kotlin bindings if feature enabled
    #[cfg(feature = "kotlin")]
    {
        uniffi::generate_scaffolding("./src/zed_mobile.udl")
            .expect("Failed to generate UniFFI bindings");
    }
}
```

### Flutter Integration

```dart
// flutter_bridge/lib/zed_mobile_bridge.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef InitNative = Pointer<FfiResult> Function();
typedef Init = Pointer<FfiResult> Function();

typedef SendMessageNative = Pointer<FfiResult> Function(Pointer<FfiString>);
typedef SendMessage = Pointer<FfiResult> Function(Pointer<FfiString>);

class ZedMobileBridge {
  late final DynamicLibrary _lib;
  late final Init _init;
  late final SendMessage _sendMessage;

  ZedMobileBridge() {
    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libzed_mobile_bridge.so')
        : DynamicLibrary.open('zed_mobile_bridge.framework/zed_mobile_bridge');

    _init = _lib
        .lookup<NativeFunction<InitNative>>('zed_mobile_init')
        .asFunction();

    _sendMessage = _lib
        .lookup<NativeFunction<SendMessageNative>>('zed_mobile_send_message')
        .asFunction();
  }

  bool initialize() {
    final result = _init();
    final success = result.ref.success;

    if (!success) {
      final error = result.ref.error.toDartString();
      throw Exception('Failed to initialize: $error');
    }

    return true;
  }

  void sendMessage(String content) {
    final contentPtr = content.toNativeUtf8();
    final ffiString = calloc<FfiString>();
    ffiString.ref.ptr = contentPtr.cast();
    ffiString.ref.len = content.length;

    final result = _sendMessage(ffiString);

    if (!result.ref.success) {
      final error = result.ref.error.toDartString();
      throw Exception('Failed to send message: $error');
    }

    calloc.free(contentPtr);
    calloc.free(ffiString);
  }
}
```

## Usage Example

### Mobile App Integration

```dart
// Flutter app usage
class AgentService {
  late final ZedMobileBridge _bridge;

  Future<void> initialize() async {
    _bridge = ZedMobileBridge();
    _bridge.initialize();

    // Set up event listeners
    _bridge.onThreadUpdate((threadInfo) {
      print('Thread updated: ${threadInfo.summary}');
    });

    _bridge.onMessage((message) {
      print('New message: ${message.content}');
    });
  }

  Future<void> sendCommand(String command) async {
    try {
      _bridge.sendMessage(command);
    } catch (e) {
      print('Error sending command: $e');
    }
  }
}
```

## Building and Deployment

### iOS Build Script

```bash
#!/bin/bash
# scripts/build-ios.sh

cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios

# Create universal library
lipo -create \
  target/aarch64-apple-ios/release/libzed_mobile_bridge.a \
  target/x86_64-apple-ios/release/libzed_mobile_bridge.a \
  -output target/universal/libzed_mobile_bridge.a

# Create framework
mkdir -p ZedMobileBridge.framework
cp target/universal/libzed_mobile_bridge.a ZedMobileBridge.framework/ZedMobileBridge
cp target/zed_mobile_bridge.h ZedMobileBridge.framework/Headers/
```

### Android Build Script

```bash
#!/bin/bash
# scripts/build-android.sh

# Build for all Android architectures
cargo ndk -t armeabi-v7a -t arm64-v8a -t x86 -t x86_64 \
  -o ./jniLibs build --release

# Copy to Android project
cp -r jniLibs/* ../mobile/android/app/src/main/jniLibs/
```

## Testing Strategy

### Rust Unit Tests

```rust
// tests/integration.rs
#[test]
fn test_runtime_initialization() {
    assert!(ZedMobileRuntime::initialize().is_ok());
}

#[test]
fn test_thread_creation() {
    ZedMobileRuntime::initialize().unwrap();
    let runtime = ZedMobileRuntime::get();

    runtime.write().gpui_runtime.run_on_main(|cx| {
        // Test thread creation
    });
}
```

### FFI Tests

```rust
// tests/ffi.rs
#[test]
fn test_ffi_string_conversion() {
    let rust_string = "Hello, Mobile!";
    let ffi_string = FfiString::from_str(rust_string);

    unsafe {
        assert_eq!(ffi_string.to_string(), rust_string);
    }
}
```

## Next Steps

1. **Implement Event Streaming**: Add WebSocket or SSE for real-time updates
2. **Add Voice Input Bridge**: Integrate voice commands through FFI
3. **Implement Caching**: Add local caching for offline support
4. **Performance Optimization**: Profile and optimize hot paths
5. **Error Handling**: Improve error propagation and recovery
6. **Documentation**: Generate API documentation for mobile developers

This bridge crate provides a solid foundation for integrating Zed's agent panel into mobile applications while maintaining type safety and performance.
