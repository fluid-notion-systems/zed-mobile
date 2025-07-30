# Zed Mobile Bridge Quick Start Guide

## Overview

This guide will help you quickly set up and start using the Zed Mobile Bridge crate to connect your mobile app with Zed's agent panel.

## Prerequisites

- Rust toolchain (1.75+)
- Flutter SDK (3.x) or Kotlin development environment
- Zed source code (as git submodule)
- Platform-specific tools:
  - **iOS**: Xcode 14+
  - **Android**: Android Studio, NDK 25+

## Step 1: Set Up the Bridge Crate

### 1.1 Create the Bridge Directory

```bash
cd zed-mobile
mkdir -p bridge/src/ffi bridge/src/bridge bridge/src/runtime
```

### 1.2 Create Cargo.toml

```bash
cat > bridge/Cargo.toml << 'EOF'
[package]
name = "zed-mobile-bridge"
version = "0.1.0"
edition = "2021"

[lib]
name = "zed_mobile_bridge"
crate-type = ["cdylib", "staticlib"]

[dependencies]
agent = { path = "../vendor/zed/crates/agent" }
agent_ui = { path = "../vendor/zed/crates/agent_ui" }
gpui = { path = "../vendor/zed/crates/gpui" }
anyhow = "1.0"
log = "0.4"
once_cell = "1.19"

[build-dependencies]
cbindgen = "0.26"
EOF
```

### 1.3 Create Initial Bridge Code

Create `bridge/src/lib.rs`:

```rust
use once_cell::sync::OnceCell;
use std::sync::Arc;
use parking_lot::RwLock;

static RUNTIME: OnceCell<Arc<RwLock<ZedRuntime>>> = OnceCell::new();

pub struct ZedRuntime {
    // Runtime state will go here
}

#[no_mangle]
pub extern "C" fn zed_mobile_init() -> bool {
    // Initialize runtime
    true
}

#[no_mangle]
pub extern "C" fn zed_mobile_test() -> i32 {
    42  // Simple test function
}
```

## Step 2: Build the Bridge

### 2.1 Install Build Tools

```bash
# For iOS
cargo install cargo-lipo

# For Android
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi
```

### 2.2 Create Build Scripts

Create `scripts/build-bridge.sh`:

```bash
#!/bin/bash
set -e

echo "Building Zed Mobile Bridge..."

# iOS
if [[ "$1" == "ios" || "$1" == "all" ]]; then
    echo "Building for iOS..."
    cargo lipo --release --manifest-path bridge/Cargo.toml
    mkdir -p mobile/ios/Frameworks
    cp target/universal/release/libzed_mobile_bridge.a mobile/ios/Frameworks/
fi

# Android
if [[ "$1" == "android" || "$1" == "all" ]]; then
    echo "Building for Android..."
    cd bridge
    cargo ndk -t arm64-v8a -t armeabi-v7a -o ../mobile/android/app/src/main/jniLibs build --release
    cd ..
fi

echo "Build complete!"
```

Make it executable:
```bash
chmod +x scripts/build-bridge.sh
```

## Step 3: Flutter Integration

### 3.1 Create FFI Bindings

Create `mobile/lib/ffi/bridge.dart`:

```dart
import 'dart:ffi';
import 'dart:io';

typedef InitNative = Bool Function();
typedef Init = bool Function();

typedef TestNative = Int32 Function();
typedef Test = int Function();

class ZedBridge {
  late final DynamicLibrary _lib;
  late final Init init;
  late final Test test;

  ZedBridge() {
    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libzed_mobile_bridge.so')
        : DynamicLibrary.process();  // iOS links statically

    init = _lib
        .lookup<NativeFunction<InitNative>>('zed_mobile_init')
        .asFunction();

    test = _lib
        .lookup<NativeFunction<TestNative>>('zed_mobile_test')
        .asFunction();
  }
}
```

### 3.2 Test the Bridge

Create a simple test in your Flutter app:

```dart
import 'package:flutter/material.dart';
import 'ffi/bridge.dart';

class BridgeTestScreen extends StatefulWidget {
  @override
  _BridgeTestScreenState createState() => _BridgeTestScreenState();
}

class _BridgeTestScreenState extends State<BridgeTestScreen> {
  late final ZedBridge _bridge;
  String _status = 'Not initialized';

  @override
  void initState() {
    super.initState();
    _bridge = ZedBridge();
    _initializeBridge();
  }

  Future<void> _initializeBridge() async {
    try {
      final success = _bridge.init();
      final testValue = _bridge.test();

      setState(() {
        _status = 'Initialized! Test value: $testValue';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Bridge Test')),
      body: Center(
        child: Text(_status),
      ),
    );
  }
}
```

## Step 4: Platform-Specific Setup

### 4.1 iOS Setup

Add to `mobile/ios/Runner/Runner-Bridging-Header.h`:
```c
#import "zed_mobile_bridge.h"
```

Update `mobile/ios/Podfile`:
```ruby
target 'Runner' do
  # ... existing content ...

  # Add this
  pod 'ZedMobileBridge', :path => '../'
end
```

### 4.2 Android Setup

Update `mobile/android/app/build.gradle`:
```gradle
android {
    // ... existing content ...

    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}
```

## Step 5: Build and Run

```bash
# Build the bridge
./scripts/build-bridge.sh all

# Run Flutter app
cd mobile
flutter run
```

## Common Issues and Solutions

### Issue: Library not found on iOS

**Solution**: Ensure the library is properly linked in Xcode:
1. Open `ios/Runner.xcworkspace`
2. Add `libzed_mobile_bridge.a` to "Link Binary With Libraries"
3. Add library search path: `$(PROJECT_DIR)/../Frameworks`

### Issue: UnsatisfiedLinkError on Android

**Solution**: Verify JNI libraries are in correct location:
```bash
ls mobile/android/app/src/main/jniLibs/arm64-v8a/
# Should show: libzed_mobile_bridge.so
```

### Issue: Rust compilation errors

**Solution**: Ensure all Zed dependencies are available:
```bash
cd vendor/zed
cargo check --all
```

## Next Steps

1. **Implement Real Features**: Replace test functions with actual agent panel access
2. **Add Event Streaming**: Implement WebSocket connection for real-time updates
3. **Error Handling**: Add proper error handling and logging
4. **Testing**: Write unit and integration tests
5. **Documentation**: Document your API for other developers

## Useful Commands

```bash
# Check FFI symbols
nm -g target/universal/release/libzed_mobile_bridge.a | grep zed_mobile

# Generate C headers
cbindgen --config cbindgen.toml --crate zed-mobile-bridge --output zed_mobile_bridge.h

# Run Rust tests
cargo test --manifest-path bridge/Cargo.toml

# Clean build
cargo clean --manifest-path bridge/Cargo.toml
rm -rf mobile/ios/Frameworks/libzed_mobile_bridge.a
rm -rf mobile/android/app/src/main/jniLibs
```

## Resources

- [Rust FFI Guide](https://doc.rust-lang.org/nomicon/ffi.html)
- [Flutter FFI Documentation](https://docs.flutter.dev/development/platform-integration/c-interop)
- [cargo-ndk Documentation](https://github.com/bbqsrc/cargo-ndk)
- [cbindgen Documentation](https://github.com/eqrion/cbindgen)

This quick start guide should get you up and running with the bridge crate. For more detailed implementation, refer to the full [Bridge Crate Implementation Plan](../research/bridge-crate-implementation.md).
