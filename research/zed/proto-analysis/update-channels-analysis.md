# UpdateChannels Proto Message Analysis

## Overview

`UpdateChannels` is the primary broadcast mechanism for channel-related state changes in Zed's collaboration system. It serves as a multiplexed notification that can carry various types of channel updates in a single message.

## Proto Definition

```proto
message UpdateChannels {
    repeated Channel channels = 1;
    repeated uint64 delete_channels = 4;
    repeated Channel channel_invitations = 5;
    repeated uint64 remove_channel_invitations = 6;
    repeated ChannelParticipants channel_participants = 7;
    repeated ChannelMessageId latest_channel_message_ids = 8;
    repeated ChannelBufferVersion latest_channel_buffer_versions = 9;
}
```

## Message Components

### 1. **channels** - Channel Updates
- Contains full channel objects with metadata
- Used when channels are created, renamed, moved, or visibility changes
- Includes channel hierarchy via `parent_path`

### 2. **delete_channels** - Channel Removals
- List of channel IDs to remove from client state
- Used when channels are deleted or user loses access

### 3. **channel_invitations** - New Invitations
- Full channel objects for channels the user is invited to
- Allows preview of channel before accepting

### 4. **remove_channel_invitations** - Cancelled Invitations
- Channel IDs where invitations were revoked or responded to

### 5. **channel_participants** - Active Users
- Maps channel IDs to lists of participant user IDs
- Updated when users join/leave channels

### 6. **latest_channel_message_ids** - Chat Updates
- Notifies about new messages without sending content
- Clients can fetch if needed

### 7. **latest_channel_buffer_versions** - Buffer State
- Version vectors for collaborative buffers
- Used for synchronization

## Server-Side Usage Patterns

### 1. **Channel Creation**
```rust
// From create_channel handler
let update = proto::UpdateChannels {
    channels: vec![channel.to_proto()],
    ..Default::default()
};
session.peer.send(connection_id, update.clone())?;
```
- Broadcasts new channel to all users with visibility permissions
- Only sent to users who can see the channel based on role

### 2. **Visibility Changes**
```rust
// From set_channel_visibility handler
let update = if role.can_see_channel(channel.visibility) {
    proto::UpdateChannels {
        channels: vec![channel.to_proto()],
        ..Default::default()
    }
} else {
    proto::UpdateChannels {
        delete_channels: vec![channel.id.to_proto()],
        ..Default::default()
    }
};
```
- Adds or removes channels based on new visibility rules
- Manages connection pool subscriptions

### 3. **Member Role Updates**
```rust
// From set_channel_member_role handler
let update = proto::UpdateChannels {
    channel_invitations: vec![channel.to_proto()],
    ..Default::default()
};
```
- Updates invitation status when roles change
- Sent to affected member's connections

### 4. **Channel Activity Notifications**
```rust
// From send_channel_message handler
proto::UpdateChannels {
    latest_channel_message_ids: vec![proto::ChannelMessageId {
        channel_id: channel_id.to_proto(),
        message_id: message_id.to_proto(),
    }],
    ..Default::default()
}
```
- Lightweight notification of new activity
- Doesn't include message content

### 5. **Participant Updates**
```rust
// From channel_updated function
proto::UpdateChannels {
    channel_participants: vec![proto::ChannelParticipants {
        channel_id: channel.id.to_proto(),
        participant_user_ids: participants.clone(),
    }],
    ..Default::default()
}
```
- Broadcasts when users join/leave channels
- Sent to all channel members

## Client-Side Handling

### 1. **Message Reception**
```rust
// In ChannelStore
client.add_message_handler(cx.weak_entity(), Self::handle_update_channels)
```

### 2. **State Updates**
The `handle_update_channels` method processes each component:
- Merges channel updates into local state
- Removes deleted channels
- Updates invitation lists
- Refreshes participant counts
- Triggers UI updates

### 3. **Subscription Flow**
```rust
// Initial subscription
client.send(proto::SubscribeToChannels {})?;

// Server builds comprehensive update
fn build_channels_update(channels: ChannelsForUser) -> proto::UpdateChannels {
    let mut update = proto::UpdateChannels::default();
    
    for channel in channels.channels {
        update.channels.push(channel.to_proto());
    }
    
    update.latest_channel_buffer_versions = channels.latest_buffer_versions;
    update.latest_channel_message_ids = channels.latest_channel_messages;
    
    // Add participants...
    
    update
}
```

## Broadcasting Strategy

### 1. **Permission-Based Filtering**
- Server checks `role.can_see_channel()` before including channels
- Private channels only sent to members
- Public channels sent to all authenticated users

### 2. **Connection Pool Management**
```rust
// Get relevant connections
for (connection_id, role) in connection_pool.channel_connection_ids(root_id) {
    if !role.can_see_channel(channel.visibility) {
        continue;
    }
    // Send update...
}
```

### 3. **Incremental Updates**
- Only sends changed data, not full state
- Clients merge updates into existing state
- Reduces bandwidth and processing

## Design Patterns

### 1. **Multiplexed Updates**
Single message type carries multiple update types, reducing:
- Number of message handlers needed
- Network round trips
- Client-side processing complexity

### 2. **Push-Based Synchronization**
- Server pushes updates immediately
- No polling required
- Ensures real-time consistency

### 3. **Partial State Transfer**
- Only sends what changed
- Clients maintain full state
- Efficient for large channel lists

### 4. **Role-Based Broadcasting**
- Built-in permission checking
- Automatic filtering based on visibility
- Secure by default

## Comparison with Agent Event Routing

The `UpdateChannels` pattern provides a template for agent events:

### Similarities
- Push-based updates to subscribed clients
- Permission-based filtering (user can only see own threads)
- Incremental state updates
- Multiplexed message types

### Differences
- Agent events are more stream-oriented (many events per operation)
- Thread ownership is simpler (user-based, not role-based)
- Events include more real-time data (streaming text, tool use)

### Implementation Guidance
For agent events, consider:
- Single `AgentEventNotification` message type
- Include event type discriminator
- Bundle related events when possible
- Use similar connection pool patterns
- Implement subscription management per thread