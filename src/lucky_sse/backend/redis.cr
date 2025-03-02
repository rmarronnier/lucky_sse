# # Redis backend for distributed client management
# module Lucky::SSE
#   class RedisBackend < Backend
#     # These are handled differently with Redis:
#     # - We store stream metadata in Redis
#     # - We don't store actual Stream objects in Redis
#     # - We rely on PubSub for broadcasting

#     @redis : Redis::Client
#     @prefix : String
#     @pubsub_channel : String

#     # Local registry to track active streams
#     @local_streams = {} of String => Stream
#     @subscription_active = false
#     @subscription_lock = Mutex.new

#     def initialize(@redis, @prefix)
#       @pubsub_channel = "#{@prefix}:broadcast"
#       @subscription_active = false
#       ensure_subscription
#     end

#     # Add a client to Redis
#     def add_client(stream : Stream)
#       # Store the stream locally for message delivery
#       @local_streams[stream.id] = stream

#       # Store stream metadata in Redis
#       key = "#{@prefix}:clients:#{stream.id}"

#       # Store basic info
#       @redis.hset(key, "created_at", Time.utc.to_unix.to_s)

#       # Store metadata
#       stream.metadata.each do |meta_key, meta_value|
#         @redis.hset(key, "meta:#{meta_key}", meta_value)
#       end

#       # Add to client set
#       @redis.sadd("#{@prefix}:clients", stream.id)

#       # Set expiration (to auto-cleanup if node crashes)
#       @redis.expire(key, 3600) # 1 hour TTL, will be refreshed on heartbeats
#     end

#     # Remove a client from Redis
#     def remove_client(stream : Stream)
#       # Remove from local registry
#       @local_streams.delete(stream.id)

#       # Remove from client set
#       @redis.srem("#{@prefix}:clients", stream.id)

#       # Delete client metadata
#       @redis.del("#{@prefix}:clients:#{stream.id}")
#     end

#     # Broadcast an event via Redis
#     def broadcast(event : String, data : String, id : String? = nil, filter : Hash(String, String)? = nil)
#       message = {
#         "event"     => event,
#         "data"      => data,
#         "id"        => id || Random::Secure.hex(8),
#         "filter"    => filter,
#         "timestamp" => Time.utc.to_unix_ms,
#       }.to_json

#       # Publish to the broadcast channel
#       @redis.publish(@pubsub_channel, message)

#       # For local clients, deliver immediately
#       local_count = deliver_to_matching_clients(event, data, id, filter)

#       # Return local count for immediate feedback
#       local_count
#     end

#     # Get count of clients from Redis
#     def client_count : Int32
#       @redis.scard("#{@prefix}:clients").as_i
#     end

#     # Clean up old clients
#     def cleanup_disconnected_clients
#       # Remove any local clients that are disconnected
#       disconnected = [] of String

#       @local_streams.each do |id, stream|
#         if stream.response.closed?
#           disconnected << id
#         end
#       end

#       disconnected.each do |id|
#         if stream = @local_streams[id]?
#           remove_client(stream)
#         end
#       end

#       # Refresh TTL for active connections
#       @local_streams.each do |id, stream|
#         @redis.expire("#{@prefix}:clients:#{id}", 3600)
#       end
#     end

#     # Subscribe to the broadcast channel
#     private def subscribe_to_broadcasts
#       return if @subscription_active

#       @subscription_lock.synchronize do
#         return if @subscription_active
#         @subscription_active = true

#         # Start subscription in separate fiber
#         spawn do
#           begin
#             # We use the same Redis client instance for subscription
#             @redis.subscribe(@pubsub_channel) do |msg, _|
#               begin
#                 # Parse the message
#                 payload = JSON.parse(msg.payload)

#                 # Extract the event details
#                 event = payload["event"].as_s
#                 data = payload["data"].as_s
#                 id = payload["id"]?.try(&.as_s) || Random::Secure.hex(8)

#                 # Extract filter if present
#                 filter = nil
#                 if filter_json = payload["filter"]?
#                   unless filter_json.as_nil?
#                     filter = Hash(String, String).new
#                     filter_json.as_h.each do |k, v|
#                       filter[k.to_s] = v.to_s
#                     end
#                   end
#                 end

#                 # Deliver to matching local clients
#                 deliver_to_matching_clients(event, data, id, filter)
#               rescue ex
#                 Log.error(exception: ex) { "Error processing SSE broadcast: #{ex.message}" }
#               end
#             end
#           rescue ex
#             Log.error(exception: ex) { "SSE Redis subscription error: #{ex.message}" }

#             # Mark subscription as inactive so it can be restarted
#             @subscription_active = false

#             # Try to restart subscription after a delay
#             spawn do
#               sleep 5
#               ensure_subscription
#             end
#           end
#         end
#       end
#     end

#     # Deliver a message to matching local clients
#     private def deliver_to_matching_clients(event : String, data : String, id : String?, filter : Hash(String, String)?) : Int32
#       count = 0
#       disconnected = [] of String

#       @local_streams.each do |client_id, stream|
#         # Skip if filter doesn't match
#         if filter && !stream.matches?(filter)
#           next
#         end

#         begin
#           stream.send(data: data, event: event, id: id)
#           count += 1
#         rescue SSEDisconnectError
#           disconnected << client_id
#         end
#       end

#       # Clean up disconnected clients
#       disconnected.each do |id|
#         if stream = @local_streams[id]?
#           remove_client(stream)
#         end
#       end

#       count
#     end

#     # Ensure Redis subscription is active
#     private def ensure_subscription
#       subscribe_to_broadcasts unless @subscription_active
#     end
#   end
# end
