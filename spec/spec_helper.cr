require "spec"
require "../src/lucky_sse"

# Custom IO class for testing that captures output
class TestIO < IO
  property buffer = IO::Memory.new

  def read(slice : Bytes) : Int32
    raise "Not implemented"
  end

  def write(slice : Bytes) : Nil
    @buffer.write(slice)
  end

  def to_s
    @buffer.to_s
  end

  def clear
    @buffer = IO::Memory.new
  end

  def flush
    # No-op for testing
  end
end

# Helper method to build a context with a test IO
def build_test_context
  request = HTTP::Request.new("GET", "/")
  io = TestIO.new
  response = HTTP::Server::Response.new(io)
  HTTP::Server::Context.new(request, response)
end

# Make to_s available on IO::Memory for spec verification
class IO::Memory
  def to_s
    String.new(to_slice)
  end
end

# Add helper extensions to make testing easier
class HTTP::Server::Response
  # Allow access to the IO for testing
  def output
    @io
  end
end

# Stub MockStreams for testing that raise specified errors
class MockStream < Lucky::SSE::Stream
  property should_fail = false

  def initialize(context)
    super(context)
  end

  def send(data, event = nil, id = nil, retry_ms = nil)
    if should_fail
      raise Lucky::SSE::SSEDisconnectError.new("Test failure")
    else
      super
    end
  end

  def heartbeat
    if should_fail
      raise Lucky::SSE::SSEDisconnectError.new("Test failure")
    else
      super
    end
  end
end
