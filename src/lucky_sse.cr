require "lucky"
require "redis"
# Optional Redis support
# begin
#   require "redis"
# rescue
  # Redis shard is not available, Redis-backed SSE functionality will be disabled
# end

require "./lucky_sse/**"

module Lucky::SSE
  VERSION = "0.1.0"

  # Backend types for client management
  enum BackendType
    InMemory # Default in-memory client management
    Redis    # Redis-backed client management for distributed setups
  end
end
