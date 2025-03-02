# Lucky SSE

A Server-Sent Events (SSE) shard for the Lucky framework, allowing easy creation of real-time event streams in Lucky applications.

## Features

- Simple API for creating SSE endpoints with minimal code
- Automatic connection management
- Heartbeats to prevent connection timeouts
- Filtering for channel-based subscriptions
- Support for metadata on connections
- Redis backend for distributed deployments
- Easy broadcast API

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  lucky_sse:
    github: yourusername/lucky_sse
```

2. Run `shards install`

## Basic Usage

Creating an SSE endpoint is as simple as adding the `sse` macro to your action:

```crystal
class EventStream::Show < BrowserAction
  # This creates:
  # - GET /events - The SSE stream
  # - GET /events/stats - Stats endpoint
  # - POST /events/broadcast - Broadcast endpoint
  sse "/events"
end
```

That's it! You now have a fully functional SSE system.

## Redis Support

For multi-server deployments, you can use Redis as a backend for client management:

```crystal
# In your application config (e.g., in src/app.cr)
Lucky::SSE.configure do |config|
  # Enable Redis backend
  config.backend_type = Lucky::SSE::BackendType::Redis

  # Configure Redis connection (default is redis://localhost:6379)
  config.redis_url = ENV["REDIS_URL"]

  # Set a unique prefix for your app (if multiple apps share the same Redis)
  config.redis_prefix = "my_app_sse"

  # Configure cleanup interval (seconds)
  config.cleanup_interval = 60
end
```

> **Note:** Make sure to add the `redis` shard to your dependencies if you want Redis support:
>
> ```yaml
> dependencies:
>   redis:
>     github: jgaskins/redis
> ```

## Custom Initialization

You can customize stream initialization with a block:

```crystal
class EventStream::Show < BrowserAction
  sse "/events" do
    # Custom initialization code
    # The stream is available as %stream
    %stream.send(
      data: { message: "Welcome!", timestamp: Time.utc.to_s }.to_json,
      event: "connection"
    )

    # You can log connections
    Log.info { "New client connected" }
  end
end
```

## Channel-Based Subscriptions

You can implement channel-based subscriptions using metadata:

```crystal
class Channels::Stream < BrowserAction
  sse "/channels" do
    # Get the channel from query params
    channel = params.get?(:channel) || "global"

    # Set channel metadata (automatically included from query params)
    %stream.set_metadata("channel", channel)

    # Send channel confirmation
    %stream.send(
      data: "Connected to channel: #{channel}",
      event: "connection"
    )
  end
end
```

Then broadcast only to that channel:

```crystal
# Broadcast only to "news" channel
filter = {"channel" => "news"}
Lucky::SSE::Handler.broadcast_event("update", "Breaking news!", filter: filter)
```

## Metadata Filtering

Metadata is automatically populated from query parameters, making it easy to create filtered subscriptions:

```
# Connect to sports channel
GET /channels?channel=sports

# Connect to user-specific notifications
GET /notifications?user_id=123
```

Then you can filter broadcasts using the same keys:

```crystal
# Send only to sports channel subscribers
Lucky::SSE::Handler.broadcast_event(
  event: "update",
  data: "Sports update!",
  filter: {"channel" => "sports"}
)

# Send only to a specific user
Lucky::SSE::Handler.broadcast_event(
  event: "notification",
  data: "New message!",
  filter: {"user_id" => "123"}
)
```

## Broadcasting from Anywhere

You can broadcast events from anywhere in your application:

```crystal
class SomeAction < BrowserAction
  get "/trigger-event" do
    # Broadcast to all clients
    Lucky::SSE::Handler.broadcast_event(
      event: "alert",
      data: "System maintenance in 5 minutes!"
    )

    html "<h1>Event sent!</h1>"
  end
end
```

## Customizing SSE Options

You can customize various SSE options:

```crystal
# Custom heartbeat interval (in seconds)
sse "/events", heartbeat_interval: 60

# Disable heartbeat
sse "/events", heartbeat_interval: 0

# Keep CSRF protection (not recommended for SSE)
sse "/events", skip_csrf: false
```

## Performance Considerations

- For single-server deployments, the in-memory backend is more efficient
- For multi-server deployments, the Redis backend is required
- Use appropriate heartbeat intervals (30-60 seconds is typical)
- Consider the number of concurrent connections your server can handle

## License

This shard is available as open source under the terms of the MIT License.
