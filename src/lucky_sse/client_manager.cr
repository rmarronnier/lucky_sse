module Lucky::SSE
  # Client manager handles client registration and broadcasting
  class ClientManager
    @@instance : ClientManager?

    # Get the singleton instance
    def self.instance
      @@instance ||= new
    end

    # Initialize the backend
    def initialize
      case Lucky::SSE.config.backend_type
      when BackendType::InMemory
        @backend = InMemoryBackend.new
      when BackendType::Redis
        {% if @top_level.has_constant?("Redis") %}
          if redis = Lucky::SSE.config.redis
            @backend = RedisBackend.new(redis, Lucky::SSE.config.redis_prefix)
          else
            # Fall back to in-memory if Redis client isn't initialized
            @backend = InMemoryBackend.new
          end
        {% else %}
          # Redis is not available, fall back to in-memory
          @backend = InMemoryBackend.new
        {% end %}
      end

      # Start the cleanup task
      ensure_cleanup_task
    end

    # Register a client
    def register(stream : Stream)
      @backend.add_client(stream)
    end

    # Unregister a client
    def unregister(stream : Stream)
      @backend.remove_client(stream)
    end

    # Broadcast to all clients
    def broadcast(event : String, data : String, id : String? = nil, filter : Hash(String, String)? = nil)
      @backend.broadcast(event, data, id, filter)
    end

    # Get client count
    def client_count : Int32
      @backend.client_count
    end

    # Clean up disconnected clients
    def cleanup_disconnected_clients
      @backend.cleanup_disconnected_clients
    end

    # Ensure the cleanup task is running
    @@cleanup_started = false

    private def ensure_cleanup_task
      return if @@cleanup_started

      spawn do
        @@cleanup_started = true
        loop do
          cleanup_disconnected_clients
          sleep Lucky::SSE.config.cleanup_interval
        end
      end
    end
  end
end
