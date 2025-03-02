require "./spec_helper"

{% if @top_level.has_constant?("Redis") %}
  # Only run these specs if Redis is available
  describe Lucky::SSE::RedisBackend do
    # Set up Redis backend for tests
    # WARNING: This connects to an actual Redis instance!
    # These tests should only be run in development environments where Redis is available
    # and these tests won't interfere with production data
    before_each do
      # Configure to use Redis backend with a test prefix
      Lucky::SSE.configure do |config|
        config.backend_type = Lucky::SSE::BackendType::Redis
        config.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379"
        config.redis_prefix = "test_lucky_sse_#{Random::Secure.hex(8)}"
      end

      # Clear any test keys
      Lucky::SSE.config.redis.try &.del("#{Lucky::SSE.config.redis_prefix}:clients")
    end

    after_each do
      # Clean up any Redis keys we created
      if redis = Lucky::SSE.config.redis
        keys = redis.keys("#{Lucky::SSE.config.redis_prefix}:*")
        keys.each do |key|
          redis.del(key)
        end
      end

      # Reset config
      Lucky::SSE.config = Lucky::SSE::Config.new
    end

    it "stores client info in Redis" do
      # Get Redis instance
      redis = Lucky::SSE.config.redis.not_nil!

      # Create a stream
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Create Redis backend
      backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

      # Add the client
      backend.add_client(stream)

      # Verify client was added to Redis
      redis.sismember("#{Lucky::SSE.config.redis_prefix}:clients", stream.id).should be_true
      redis.exists("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}").should be_true
    end

    it "stores metadata in Redis" do
      # Get Redis instance
      redis = Lucky::SSE.config.redis.not_nil!

      # Create a stream with metadata
      context = build_context
      stream = Lucky::SSE::Stream.new(context, metadata: {"channel" => "test"})

      # Create Redis backend
      backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

      # Add the client
      backend.add_client(stream)

      # Verify metadata was stored
      redis.hget("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}", "meta:channel").should eq("test")
    end

    it "removes client info from Redis" do
      # Get Redis instance
      redis = Lucky::SSE.config.redis.not_nil!

      # Create a stream
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Create Redis backend
      backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

      # Add then remove the client
      backend.add_client(stream)
      backend.remove_client(stream)

      # Verify client was removed from Redis
      redis.sismember("#{Lucky::SSE.config.redis_prefix}:clients", stream.id).should be_false
      redis.exists("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}").should be_false
    end

    it "broadcasts via Redis publish" do
      # Get Redis instance
      redis = Lucky::SSE.config.redis.not_nil!

      # Create Redis backend
      backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

      # Set up a subscriber to validate the publish
      channel = "#{Lucky::SSE.config.redis_prefix}:broadcast"
      received_message = nil

      # Subscribe in a separate fiber
      spawn do
        redis.subscribe(channel) do |on|
          on.message do |channel, message|
            received_message = message
            redis.unsubscribe(channel)
          end
        end
      end

      # Wait a moment for subscription to be ready
      sleep 0.1

      # Send a broadcast
      backend.broadcast("test_event", "test data")

      # Wait for the message to be received
      sleep 0.1

      # Verify the message was published
      received_message.should_not be_nil
      if received_message
        parsed = JSON.parse(received_message)
        parsed["event"].should eq("test_event")
        parsed["data"].should eq("test data")
      end
    end

    it "tracks client count in Redis" do
      # Get Redis instance
      redis = Lucky::SSE.config.redis.not_nil!

      # Create Redis backend
      backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

      # Verify initial count
      backend.client_count.should eq(0)

      # Add some clients
      context1 = build_context
      context2 = build_context
      stream1 = Lucky::SSE::Stream.new(context1)
      stream2 = Lucky::SSE::Stream.new(context2)

      backend.add_client(stream1)
      backend.client_count.should eq(1)

      backend.add_client(stream2)
      backend.client_count.should eq(2)

      # Remove a client
      backend.remove_client(stream1)
      backend.client_count.should eq(1)
    end
  end
{% end %}
