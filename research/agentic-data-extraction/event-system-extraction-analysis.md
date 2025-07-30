# Event System Extraction Analysis: Avoiding GPUI Dependencies

## Overview

This document analyzes the challenge of extracting or creating an event system for `zed-agent-core` without introducing GPUI dependencies. The goal is to enable real-time event streaming while maintaining a clean separation between core data structures and Zed's UI framework.

## 1. Current State: Zed's Event Systems

### 1.1 GPUI-Coupled Event Mechanisms

```rust
// Tightly coupled to GPUI's ModelContext
cx.observe(entity, |this, other, cx| {
    // Handle changes
});

cx.subscribe(entity, |this, event, cx| {
    // Handle specific events
});

cx.emit(SomeEvent { ... });
cx.notify(); // Triggers observers
```

**Problems**:
- Requires `ModelContext` (cx)
- Events flow through GPUI's entity system
- Observers tied to GPUI lifecycle
- No standalone event bus

### 1.2 Entity System Dependencies

```rust
pub struct Thread {
    // GPUI entities are core to the design
    messages: Vec<Entity<Message>>,
}

// Events are methods on ModelContext
impl Thread {
    fn update(&mut self, cx: &mut ModelContext<Self>) {
        cx.emit(ThreadEvent::Updated);
    }
}
```

### 1.3 Subscription Management

GPUI subscriptions are managed internally with:
- Weak references to prevent cycles
- Automatic cleanup on drop
- Type-safe event dispatch
- Built into the framework

## 2. Extraction Challenges

### 2.1 Deep Framework Integration

GPUI events are not just a feature—they're fundamental to how Zed works:

```rust
// This pattern is everywhere
impl SomeType {
    fn do_something(&mut self, cx: &mut ModelContext<Self>) {
        // All state changes go through cx
        self.state = new_state;
        cx.notify(); // Triggers UI updates
    }
}
```

### 2.2 Type System Coupling

```rust
// GPUI uses phantom types and complex generics
pub struct Subscription<T, E> {
    _phantom: PhantomData<(T, E)>,
    // Internal GPUI machinery
}

// Events often reference GPUI types
pub enum WorkspaceEvent {
    PaneAdded(Entity<Pane>),
    ItemAdded(Box<dyn ItemHandle>),
}
```

### 2.3 Async Integration

GPUI's event system is integrated with its async runtime:
- Tasks scheduled through `cx.spawn()`
- Async observers and effects
- UI update batching

## 3. Potential Extraction Strategies

### 3.1 Strategy 1: Pure Event Bus (Recommended)

Create a completely independent event system for `zed-agent-core`:

```rust
// In zed-agent-core, no GPUI dependencies
pub struct EventBus<E> {
    subscribers: Arc<RwLock<Vec<Box<dyn Fn(&E) + Send + Sync>>>>,
}

impl<E: Clone> EventBus<E> {
    pub fn emit(&self, event: E) {
        let subscribers = self.subscribers.read().unwrap();
        for subscriber in subscribers.iter() {
            subscriber(&event);
        }
    }
    
    pub fn subscribe<F>(&self, handler: F) -> SubscriptionId
    where
        F: Fn(&E) + Send + Sync + 'static,
    {
        let mut subscribers = self.subscribers.write().unwrap();
        subscribers.push(Box::new(handler));
        SubscriptionId(subscribers.len() - 1)
    }
}
```

**Pros**:
- Zero GPUI dependencies
- Simple and focused
- Easy to test
- Can be used in any Rust project

**Cons**:
- Need to bridge with GPUI events
- Duplicate event infrastructure
- Manual subscription management

### 3.2 Strategy 2: Event Traits with Adapters

Define trait interfaces that both GPUI and core can implement:

```rust
// In zed-agent-core
pub trait EventEmitter<E> {
    fn emit(&self, event: E);
}

pub trait EventSubscriber<E> {
    type Handle;
    fn subscribe<F>(&self, handler: F) -> Self::Handle
    where F: Fn(E) + 'static;
}

// In Zed's agent crate
struct GpuiEventAdapter<T> {
    cx: ModelContext<T>,
}

impl<T, E> EventEmitter<E> for GpuiEventAdapter<T> {
    fn emit(&self, event: E) {
        // Convert to GPUI event
        self.cx.emit(GpuiEvent::Core(event));
    }
}
```

**Pros**:
- Abstraction over different event systems
- Can swap implementations
- Type-safe

**Cons**:
- Complex adapter code
- Potential performance overhead
- Trait object complications

### 3.3 Strategy 3: Message Passing

Use channels for loose coupling:

```rust
// In zed-agent-core
pub struct EventStream<E> {
    sender: mpsc::Sender<E>,
    receiver: Arc<Mutex<mpsc::Receiver<E>>>,
}

// In agent crate
impl Thread {
    fn update(&mut self, cx: &mut ModelContext<Self>) {
        // Update state
        self.core.status = ThreadStatus::Active;
        
        // Send event through channel
        if let Some(tx) = &self.event_tx {
            let _ = tx.send(AgentEvent::ThreadUpdated {
                id: self.core.id.clone(),
            });
        }
        
        // Still notify GPUI
        cx.notify();
    }
}
```

**Pros**:
- Complete decoupling
- Works across thread boundaries
- Natural async integration

**Cons**:
- Async complexity
- Memory overhead
- Potential for event loss

## 4. Recommended Approach: Hybrid Architecture

### 4.1 Core Event Bus

Create a minimal event bus in `zed-agent-core`:

```rust
// zed-agent-core/src/events/bus.rs
pub struct EventBus {
    listeners: Arc<RwLock<HashMap<TypeId, Vec<Box<dyn Any + Send + Sync>>>>>,
}

impl EventBus {
    pub fn emit<E: Event>(&self, event: E) {
        let type_id = TypeId::of::<E>();
        if let Some(listeners) = self.listeners.read().unwrap().get(&type_id) {
            for listener in listeners {
                if let Some(handler) = listener.downcast_ref::<Box<dyn Fn(&E) + Send + Sync>>() {
                    handler(&event);
                }
            }
        }
    }
}
```

### 4.2 Bridge Pattern in Agent

```rust
// In agent crate
pub struct EventBridge {
    core_bus: Arc<EventBus>,
    // Don't store ModelContext - pass it in methods
}

impl EventBridge {
    pub fn emit_with_gpui<E: Event>(
        &self,
        event: E,
        cx: &mut ModelContext<impl Any>
    ) {
        // Emit to core bus
        self.core_bus.emit(event.clone());
        
        // Also emit GPUI event
        cx.emit(AgentGpuiEvent::FromCore(Box::new(event)));
    }
}
```

### 4.3 Clean Separation

```
┌─────────────────────────┐
│   zed-agent-core       │
│  - EventBus            │
│  - AgentEvent enum     │
│  - No GPUI deps        │
└────────────┬───────────┘
             │
┌────────────▼───────────┐
│   agent (in Zed)       │
│  - EventBridge         │
│  - GPUI integration    │
│  - ModelContext usage  │
└────────────────────────┘
```

## 5. Implementation Guidelines

### 5.1 What Goes in Core

✅ **Include**:
- Simple event types (enums, structs)
- Basic pub/sub mechanism
- Event serialization
- Event filtering/routing

❌ **Exclude**:
- Any GPUI types
- ModelContext references
- Entity<T> types
- UI-specific events

### 5.2 Event Design Principles

```rust
// Good: Pure data
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessageAddedEvent {
    pub thread_id: ThreadId,
    pub message: Message,
}

// Bad: GPUI references
pub struct MessageAddedEvent {
    pub thread: Entity<Thread>, // ❌ GPUI type
    pub cx: ModelContext<Thread>, // ❌ GPUI type
}
```

### 5.3 Bridge Implementation

```rust
// Keep GPUI stuff in the agent crate
impl Thread {
    fn setup_event_bridge(&mut self, core_bus: Arc<EventBus>, cx: &mut ModelContext<Self>) {
        // Subscribe to core events
        core_bus.subscribe(move |event: &AgentEvent| {
            // Handle core events, maybe trigger GPUI updates
        });
        
        // Subscribe to GPUI events
        cx.observe(self.some_entity, move |this, _, cx| {
            // Convert GPUI events to core events
            core_bus.emit(AgentEvent::Something);
        });
    }
}
```

## 6. Alternative: Accept the Separation

### 6.1 Independent Event Systems

Perhaps the cleanest approach is to accept that we need two event systems:

1. **Core Events**: For `zed-agent-core` and external consumers
2. **GPUI Events**: For Zed's UI updates

```rust
// They serve different purposes
impl Thread {
    fn add_message(&mut self, msg: Message, cx: &mut ModelContext<Self>) {
        // Update core data
        self.core.messages.push(msg.clone());
        
        // Emit core event (for external consumers)
        self.core_events.emit(AgentEvent::MessageAdded { ... });
        
        // Emit GPUI event (for UI updates)
        cx.emit(ThreadEvent::MessageAdded);
        cx.notify();
    }
}
```

### 6.2 Benefits of Separation

- **Clear boundaries**: Core vs UI events
- **No abstraction overhead**: Each system optimized for its use case
- **Easier to understand**: No complex bridging code
- **Future-proof**: Can evolve independently

## 7. Risks and Mitigations

### 7.1 Risk: Event Synchronization

**Problem**: Core and GPUI events could get out of sync

**Mitigation**: 
- Single source of truth for state changes
- Events are derived from state, not vice versa
- Comprehensive testing

### 7.2 Risk: Performance Overhead

**Problem**: Duplicate event dispatch

**Mitigation**:
- Lazy event emission (only if subscribers exist)
- Event batching for high-frequency updates
- Profile and optimize hot paths

### 7.3 Risk: Complexity

**Problem**: Two event systems to maintain

**Mitigation**:
- Keep core event system minimal
- Clear documentation on when to use which
- Helper macros to reduce boilerplate

## 8. Recommendation

**Recommended Approach**: Implement a minimal, standalone event bus in `zed-agent-core` that:

1. Has zero GPUI dependencies
2. Focuses on agent-specific events only
3. Uses simple pub/sub pattern
4. Integrates with GPUI through a bridge in the agent crate

**Key Principles**:
- Don't try to abstract over GPUI's event system
- Accept that some duplication is better than tight coupling
- Keep the core event system focused and simple
- Use the bridge pattern for integration

**Next Steps**:
1. Implement basic EventBus in `zed-agent-core`
2. Define core AgentEvent enum
3. Create EventBridge in agent crate
4. Test with simple use case
5. Iterate based on performance and usability

This approach provides the real-time event streaming needed for the mobile app while maintaining a clean architectural boundary between core data structures and Zed's UI framework.