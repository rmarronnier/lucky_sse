class Lucky::SSE::Configuration
  property heartbeat_interval : Time::Span = 20.seconds
  property default_producer : String = "lucky_sse"
  property adapter : Lucky::SSE::Adapter = Lucky::SSE::Adapters::Memory.new
end
