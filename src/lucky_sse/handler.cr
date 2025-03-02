module Lucky::SSE
  # Mixin module to add SSE functionality to Lucky actions
  module Handler
    # Broadcast an event to all connected clients
    def self.broadcast_event(event : String, data : String, id : String? = nil, filter : Hash(String, String)? = nil)
      ClientManager.instance.broadcast(event, data, id, filter)
    end

    # Get the current number of connected clients
    def self.client_count : Int32
      ClientManager.instance.client_count
    end

    # Clean up disconnected clients
    def self.cleanup_disconnected_clients
      ClientManager.instance.cleanup_disconnected_clients
    end

    # Create and return an SSE stream with automatic management
    def sse_stream(headers : HTTP::Headers? = nil, heartbeat_interval : Float64 = 30.0, metadata : Hash(String, String) = {} of String => String) : Stream
      # Create the stream with metadata
      stream = Stream.new(context, headers, metadata)

      # Register with client manager
      ClientManager.instance.register(stream)

      # We can't directly detect client disconnections in Crystal HTTP
      # So we'll rely on error handling to detect disconnections
      # and the cleanup task to remove disconnected clients

      # Set up heartbeat if requested
      if heartbeat_interval > 0
        spawn do
          loop do
            begin
              sleep heartbeat_interval
              stream.heartbeat
            rescue SSEDisconnectError
              ClientManager.instance.unregister(stream)
              break
            end
          end
        end
      end

      # Return the stream for further use
      stream
    end

    # Helper method to keep a connection open until disconnected
    def keep_sse_connection_alive(stream : Stream)
      begin
        # This will keep the connection open until an exception is raised
        sleep
      rescue SSEDisconnectError
        # Client disconnected, make sure it's unregistered
        ClientManager.instance.unregister(stream)
      end
    end

    # Macro for defining an SSE endpoint with a single line
    macro sse(path, skip_csrf = true, heartbeat_interval = 30, &block)
       get {{ path }} do
         {% if skip_csrf %}
           # Skip CSRF protection for SSE endpoints
           skip :protect_from_forgery
         {% end %}

         # Get metadata from query params if any
         metadata = Hash(String, String).new
         request.query_params.each do |key, value|
           metadata[key] = value
         end

         # Create an SSE stream with automatic connection management
         stream = sse_stream(heartbeat_interval: {{ heartbeat_interval }}, metadata: metadata)

         # Run custom initializer code if provided
         {% if block %}
           # Make stream accessible to the block
           %stream = stream

           # Run the provided block with access to the stream
           {{ block.body }}
         {% else %}
           # Default welcome message if no block is provided
           stream.send(data: "Connected to event stream", event: "connection", id: Random::Secure.hex(8))
         {% end %}

         # Keep the connection open until client disconnects
         keep_sse_connection_alive(stream)
       end

       # Define stats endpoint
       get {{ path }} + "/stats" do
         # Clean up any disconnected clients
         Lucky::SSE::Handler.cleanup_disconnected_clients

         # Return stats as JSON
         json({
           connected_clients: Lucky::SSE::Handler.client_count,
           timestamp: Time.utc.to_s,
           backend: Lucky::SSE.config.backend_type.to_s
         })
       end

       # Define broadcast endpoint
       post {{ path }} + "/broadcast" do
         # Parse the message from the request
         message = params.get(:message)
         event_type = params.get(:event_type, "message")
         id = params.get?(:id) || Random::Secure.hex(8)

         # Get filter params if any
         filter = nil
         if filter_params = params.get?(:filter)
           begin
             filter = Hash(String, String).from_json(filter_params)
           rescue
             # Invalid filter format, ignore it
           end
         end

         # Broadcast to matching clients
         clients_reached = Lucky::SSE::Handler.broadcast_event(event_type, message, id, filter)

         # Return success status and clients info
         json({
           success: true,
           clients: Lucky::SSE::Handler.client_count,
           clients_reached: clients_reached
         })
       end
     end
  end
end

# Extension for Lucky::Action to include the SSE handler functionality
class Lucky::Action
  include Lucky::SSE::Handler
end
