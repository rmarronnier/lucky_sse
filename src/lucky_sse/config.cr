module Lucky::SSE
  # Configuration for the SSE module
  class Config
    property backend_type : BackendType = BackendType::InMemory
    property redis_url : String = "redis://localhost:6379"
    property redis_prefix : String = "lucky_sse"
    property cleanup_interval : Int32 = 60 # Seconds

    # Redis client instance (if Redis backend is used)
    getter redis : Redis::PooledClient?

    def initialize
      # Check if Redis is available
      {% if @top_level.has_constant?("Redis") %}
        # Redis is available but not used by default
      {% else %}
        # Force InMemory backend if Redis is not available
        @backend_type = BackendType::InMemory
      {% end %}
    end

    # Initialize Redis connection
    def setup_redis
      {% if @top_level.has_constant?("Redis") %}
        if @backend_type == BackendType::Redis
          @redis = Redis::PooledClient.new(url: @redis_url)
        end
      {% end %}
    end
  end

  # Global configuration
  class_property config = Config.new

  # Configure the SSE module
  def self.configure(&)
    yield config

    # Set up Redis if needed
    config.setup_redis
  end
end
