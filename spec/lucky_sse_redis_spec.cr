# require "./spec_helper"

# {% if @top_level.has_constant?("Redis") %}
#   # Helper method to create test contexts for Redis specs
#   private def build_redis_context
#     request = HTTP::Request.new("GET", "/")
#     response = HTTP::Server::Response.new(IO::Memory.new)
#     HTTP::Server::Context.new(request, response)
#   end

#   # Only run these specs if Redis is available
#   describe Lucky::SSE::RedisBackend do
#     # Set up Redis backend for tests
#     # WARNING: This connects to an actual Redis instance!
#     # These tests should only be run in development environments where Redis is available
#     # and these tests won't interfere with production data
#     before_each do
#       # Configure to use Redis backend with a test prefix
#       Lucky::SSE.configure do |config|
#         config.backend_type = Lucky::SSE::BackendType::Redis
#         config.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379"
#         config.redis_prefix = "test_lucky_sse_#{Random::Secure.hex(8)}"
#       end

#       # Clear any test keys
#       Lucky::SSE.config.redis.try &.del("#{Lucky::SSE.config.redis_prefix}:clients")
#     end

#     after_each do
#       # Clean up any Redis keys we created
#       if redis = Lucky::SSE.config.redis
#         keys_value = redis.keys("#{Lucky::SSE.config.redis_prefix}:*")
#         if keys_value.is_a?(Array)
#           string_keys = keys_value.map(&.to_s)
#           # Delete each key individually
#           string_keys.each do |key|
#             redis.del(key)
#           end
#         end
#       end

#       # Reset config
#       Lucky::SSE.config = Lucky::SSE::Config.new
#     end

#     it "stores client info in Redis" do
#       # Get Redis instance
#       redis = Lucky::SSE.config.redis.not_nil!

#       # Create a stream
#       context = build_redis_context
#       stream = Lucky::SSE::Stream.new(context)

#       # Create Redis backend
#       backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

#       # Add the client
#       backend.add_client(stream)

#       # Verify client was added to Redis
#       redis.sismember("#{Lucky::SSE.config.redis_prefix}:clients", stream.id).as_bool.should be_true
#       redis.exists("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}").as_i.should eq(1)
#     end

#     it "stores metadata in Redis" do
#       # Get Redis instance
#       redis = Lucky::SSE.config.redis.not_nil!

#       # Create a stream with metadata
#       context = build_redis_context
#       stream = Lucky::SSE::Stream.new(context, metadata: {"channel" => "test"})

#       # Create Redis backend
#       backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

#       # Add the client
#       backend.add_client(stream)

#       # Verify metadata was stored
#       redis.hget("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}", "meta:channel").to_s.should eq("test")
#     end

#     it "removes client info from Redis" do
#       # Get Redis instance
#       redis = Lucky::SSE.config.redis.not_nil!

#       # Create a stream
#       context = build_redis_context
#       stream = Lucky::SSE::Stream.new(context)

#       # Create Redis backend
#       backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

#       # Add then remove the client
#       backend.add_client(stream)
#       backend.remove_client(stream)

#       # Verify client was removed from Redis
#       redis.sismember("#{Lucky::SSE.config.redis_prefix}:clients", stream.id).as_bool.should be_false
#       redis.exists("#{Lucky::SSE.config.redis_prefix}:clients:#{stream.id}").as_i.should eq(0)
#     end

#     it "broadcasts via Redis publish" do
#       # Get Redis instance
#       redis = Lucky::SSE.config.redis.not_nil!

#       # Create Redis backend
#       backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

#       # Set up a subscriber to validate the publish
#       channel = "#{Lucky::SSE.config.redis_prefix}:broadcast"
#       received_message = nil

#       # Subscribe in a separate fiber
#       subscriber = Redis::Client.new(url: redis.connection_string)
#       subscription_done = Channel(Bool).new

#       spawn do
#         begin
#           subscriber.subscribe(channel) do |msg|
#             received_message = msg.payload
#             subscriber.unsubscribe(channel)
#             subscription_done.send(true)
#           end
#         rescue ex
#           Log.error { "Subscription error: #{ex.message}" }
#           subscription_done.send(false)
#         end
#       end

#       # Wait a moment for subscription to be ready
#       sleep 0.1

#       # Send a broadcast
#       backend.broadcast("test_event", "test data")

#       # Wait for the message to be received (with timeout)
#       select
#       when subscription_done.receive
#         # Subscription completed
#       when timeout(1.second)
#         fail "Subscription timed out"
#       end

#       # Verify the message was published
#       received_message.should_not be_nil
#       if received_message
#         parsed = JSON.parse(received_message)
#         parsed["event"].should eq("test_event")
#         parsed["data"].should eq("test data")
#       end
#     end

#     it "tracks client count in Redis" do
#       # Get Redis instance
#       redis = Lucky::SSE.config.redis.not_nil!

#       # Create Redis backend
#       backend = Lucky::SSE::RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)

#       # Verify initial count
#       backend.client_count.should eq(0)

#       # Add some clients
#       context1 = build_redis_context
#       context2 = build_redis_context
#       stream1 = Lucky::SSE::Stream.new(context1)
#       stream2 = Lucky::SSE::Stream.new(context2)

#       backend.add_client(stream1)
#       backend.client_count.should eq(1)

#       backend.add_client(stream2)
#       backend.client_count.should eq(2)

#       # Remove a client
#       backend.remove_client(stream1)
#       backend.client_count.should eq(1)
#     end
#   end
# {% end %}
