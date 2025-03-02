# Redis backend for distributed client management
{% if @top_level.has_constant?("Redis") %}
  module Lucky::SSE
    class RedisBackend < Backend
      # These are handled differently with Redis:
      # - We store stream metadata in Redis
      # - We don't store actual Stream objects in Redis
      # - We rely on PubSub for broadcasting

      @redis : Redis::PooledClient
      @prefix : String
      @pubsub_channel : String

      def initialize(@redis, @prefix)
        @pubsub_channel = "#{@prefix}:broadcast"

        # Start the Redis subscription in a separate fiber
        spawn do
          subscribe_to_broadcasts
        end
      end

      # Add a client to Redis
      def add_client(stream : Stream)
        # Store stream metadata in Redis
        key = "#{@prefix}:clients:#{stream.id}"

        # Store basic info
        @redis.hset(key, "created_at", Time.utc.to_unix.to_s)

        # Store metadata
        stream.metadata.each do |meta_key, meta_value|
          @redis.hset(key, "meta:#{meta_key}", meta_value)
        end

        # Add to client set
        @redis.sadd("#{@prefix}:clients", stream.id)
      end

      # Remove a client from Redis
      def remove_client(stream : Stream)
        # Remove from client set
        @redis.srem("#{@prefix}:clients", stream.id)

        # Delete client metadata
        @redis.del("#{@prefix}:clients:#{stream.id}")
      end

      # Broadcast an event via Redis
      def broadcast(event : String, data : String, id : String? = nil, filter : Hash(String, String)? = nil)
        # We don't know how many clients will receive this
        # The actual sending happens on each node via PubSub
        message = {
          "event"     => event,
          "data"      => data,
          "id"        => id || Random::Secure.hex(8),
          "filter"    => filter,
          "timestamp" => Time.utc.to_unix_ms,
        }.to_json

        # Publish to the broadcast channel
        @redis.publish(@pubsub_channel, message)

        # Return -1 to indicate unknown number of clients (distributed)
        -1
      end

      # Get count of clients from Redis
      def client_count : Int32
        @redis.scard("#{@prefix}:clients").to_i
      end

      # Clean up old clients
      def cleanup_disconnected_clients
        # In Redis backend, we rely on TTLs and heartbeats
        # Each node is responsible for cleaning up its own connections
      end

      # Subscribe to the broadcast channel
      private def subscribe_to_broadcasts
        # This isn't actually implemented in this example
        # In a real implementation, you would:
        # 1. Subscribe to @pubsub_channel
        # 2. Process incoming messages
        # 3. Apply filters
        # 4. Forward messages to matching local clients
        #
        # However, this requires maintaining a local registry of streams alongside
        # the Redis registry, which is beyond the scope of this example
      end
    end
  end
{% end %}
