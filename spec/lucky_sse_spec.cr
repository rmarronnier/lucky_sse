require "./spec_helper"

describe Lucky::SSE do
  it "has a version" do
    Lucky::SSE::VERSION.should be_a(String)
  end

  describe Lucky::SSE::Stream do
    it "initializes with required headers" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      headers = context.response.headers
      headers["Content-Type"].should eq("text/event-stream")
      headers["Cache-Control"].should eq("no-cache")
      headers["Connection"].should eq("keep-alive")
    end

    it "accepts custom headers" do
      context = build_context
      custom_headers = HTTP::Headers{"X-Custom" => "test"}
      stream = Lucky::SSE::Stream.new(context, custom_headers)

      headers = context.response.headers
      headers["X-Custom"].should eq("test")
    end

    it "accepts metadata" do
      context = build_context
      metadata = {"channel" => "test", "user_id" => "123"}
      stream = Lucky::SSE::Stream.new(context, metadata: metadata)

      stream.get_metadata("channel").should eq("test")
      stream.get_metadata("user_id").should eq("123")
    end

    it "can update metadata" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      stream.set_metadata("test", "value")
      stream.get_metadata("test").should eq("value")

      stream.set_metadata("test", "updated")
      stream.get_metadata("test").should eq("updated")
    end

    it "correctly matches metadata criteria" do
      context = build_context
      metadata = {"channel" => "news", "region" => "europe"}
      stream = Lucky::SSE::Stream.new(context, metadata: metadata)

      stream.matches?({"channel" => "news"}).should be_true
      stream.matches?({"region" => "europe"}).should be_true
      stream.matches?({"channel" => "news", "region" => "europe"}).should be_true
      stream.matches?({"channel" => "sports"}).should be_false
      stream.matches?({"channel" => "news", "region" => "asia"}).should be_false
    end

    it "sends formatted events" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Capture the output
      output = IO::Memory.new
      allow(context.response.output).to receive(:print).and_return { |message| output << message }
      allow(context.response.output).to receive(:flush)

      # Send a simple event
      stream.send(data: "test")

      # Verify the output format
      output.to_s.should eq("data: test\n\n")

      # Reset the output
      output.clear

      # Send an event with all options
      stream.send(
        data: "test data",
        event: "test_event",
        id: "123",
        retry_ms: 1000
      )

      # Verify the output format
      output_str = output.to_s
      output_str.should contain("event: test_event\n")
      output_str.should contain("id: 123\n")
      output_str.should contain("retry: 1000\n")
      output_str.should contain("data: test data\n")
      output_str.should end_with("\n\n")
    end

    it "sends multiline data correctly" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Capture the output
      output = IO::Memory.new
      allow(context.response.output).to receive(:print).and_return { |message| output << message }
      allow(context.response.output).to receive(:flush)

      # Send multiline data
      stream.send(data: "line 1\nline 2\nline 3")

      # Verify each line is prefixed with "data: "
      output_str = output.to_s
      output_str.should eq("data: line 1\ndata: line 2\ndata: line 3\n\n")
    end

    it "sends heartbeat" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Capture the output
      output = IO::Memory.new
      allow(context.response.output).to receive(:print).and_return { |message| output << message }
      allow(context.response.output).to receive(:flush)

      # Send a heartbeat
      stream.heartbeat

      # Verify the output format
      output.to_s.should eq(": heartbeat\n\n")
    end

    it "raises SSEDisconnectError when client disconnects" do
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Simulate IO error
      allow(context.response.output).to receive(:print).and_raise(IO::Error.new("Broken pipe"))

      # Expect SSEDisconnectError
      expect_raises(Lucky::SSE::SSEDisconnectError) do
        stream.send(data: "test")
      end

      # Also for heartbeat
      expect_raises(Lucky::SSE::SSEDisconnectError) do
        stream.heartbeat
      end
    end
  end

  describe Lucky::SSE::InMemoryBackend do
    it "manages clients" do
      backend = Lucky::SSE::InMemoryBackend.new
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Initially empty
      backend.client_count.should eq(0)

      # Add a client
      backend.add_client(stream)
      backend.client_count.should eq(1)

      # Remove a client
      backend.remove_client(stream)
      backend.client_count.should eq(0)
    end

    it "broadcasts to all clients" do
      backend = Lucky::SSE::InMemoryBackend.new
      context1 = build_context
      context2 = build_context
      stream1 = Lucky::SSE::Stream.new(context1)
      stream2 = Lucky::SSE::Stream.new(context2)

      # Add clients
      backend.add_client(stream1)
      backend.add_client(stream2)

      # Capture outputs
      output1 = IO::Memory.new
      output2 = IO::Memory.new
      allow(context1.response.output).to receive(:print).and_return { |message| output1 << message }
      allow(context2.response.output).to receive(:print).and_return { |message| output2 << message }
      allow(context1.response.output).to receive(:flush)
      allow(context2.response.output).to receive(:flush)

      # Broadcast to all
      clients_reached = backend.broadcast("test_event", "test data")

      # Verify both clients received the message
      clients_reached.should eq(2)
      output1.to_s.should contain("event: test_event\n")
      output1.to_s.should contain("data: test data\n")
      output2.to_s.should contain("event: test_event\n")
      output2.to_s.should contain("data: test data\n")
    end

    it "broadcasts with filters" do
      backend = Lucky::SSE::InMemoryBackend.new

      # Create streams with different metadata
      context1 = build_context
      context2 = build_context
      context3 = build_context

      stream1 = Lucky::SSE::Stream.new(context1, metadata: {"channel" => "news"})
      stream2 = Lucky::SSE::Stream.new(context2, metadata: {"channel" => "sports"})
      stream3 = Lucky::SSE::Stream.new(context3, metadata: {"channel" => "news"})

      # Add all clients
      backend.add_client(stream1)
      backend.add_client(stream2)
      backend.add_client(stream3)

      # Capture outputs
      output1 = IO::Memory.new
      output2 = IO::Memory.new
      output3 = IO::Memory.new
      allow(context1.response.output).to receive(:print).and_return { |message| output1 << message }
      allow(context2.response.output).to receive(:print).and_return { |message| output2 << message }
      allow(context3.response.output).to receive(:print).and_return { |message| output3 << message }
      allow(context1.response.output).to receive(:flush)
      allow(context2.response.output).to receive(:flush)
      allow(context3.response.output).to receive(:flush)

      # Broadcast only to news channel
      clients_reached = backend.broadcast("update", "news update", nil, {"channel" => "news"})

      # Verify only news channels received the message
      clients_reached.should eq(2)
      output1.to_s.should contain("event: update\n")
      output1.to_s.should contain("data: news update\n")
      output2.to_s.should be_empty
      output3.to_s.should contain("event: update\n")
      output3.to_s.should contain("data: news update\n")
    end

    it "handles disconnected clients during broadcast" do
      backend = Lucky::SSE::InMemoryBackend.new
      context1 = build_context
      context2 = build_context
      stream1 = Lucky::SSE::Stream.new(context1)
      stream2 = Lucky::SSE::Stream.new(context2)

      # Add clients
      backend.add_client(stream1)
      backend.add_client(stream2)

      # Simulate one client disconnecting
      allow(context1.response.output).to receive(:print).and_raise(Lucky::SSE::SSEDisconnectError.new("Client disconnected"))
      allow(context1.response.output).to receive(:flush).and_raise(Lucky::SSE::SSEDisconnectError.new("Client disconnected"))

      # Capture output for the second client
      output2 = IO::Memory.new
      allow(context2.response.output).to receive(:print).and_return { |message| output2 << message }
      allow(context2.response.output).to receive(:flush)

      # Broadcast should continue despite the error
      clients_reached = backend.broadcast("test", "message")

      # Only the second client should receive it
      clients_reached.should eq(1)
      output2.to_s.should contain("data: message\n")
    end
  end

  describe Lucky::SSE::ClientManager do
    it "uses the configured backend type" do
      # Reset config to defaults
      Lucky::SSE.config = Lucky::SSE::Config.new

      # Default should be InMemory
      Lucky::SSE.config.backend_type.should eq(Lucky::SSE::BackendType::InMemory)

      # Create a new client manager
      manager = Lucky::SSE::ClientManager.new

      # It should use the InMemoryBackend
      backend = typeof(manager.@backend)
      backend.should eq(Lucky::SSE::InMemoryBackend)
    end

    it "delegates methods to the backend" do
      manager = Lucky::SSE::ClientManager.new
      context = build_context
      stream = Lucky::SSE::Stream.new(context)

      # Initially empty
      manager.client_count.should eq(0)

      # Register a client
      manager.register(stream)
      manager.client_count.should eq(1)

      # Unregister a client
      manager.unregister(stream)
      manager.client_count.should eq(0)
    end
  end

  {% if @top_level.has_constant?("Redis") %}
    describe "Redis backend" do
      # These specs require a running Redis server
      # They're conditionally included only if the Redis shard is available

      it "configures Redis backend" do
        # Set up Redis config
        Lucky::SSE.configure do |config|
          config.backend_type = Lucky::SSE::BackendType::Redis
          config.redis_url = "redis://localhost:6379"
          config.redis_prefix = "test_lucky_sse"
        end

        Lucky::SSE.config.backend_type.should eq(Lucky::SSE::BackendType::Redis)
        Lucky::SSE.config.redis_url.should eq("redis://localhost:6379")
        Lucky::SSE.config.redis_prefix.should eq("test_lucky_sse")

        # Reset config for other tests
        Lucky::SSE.config = Lucky::SSE::Config.new
      end

      # More Redis-specific tests would go here, but they require a running Redis server
      # and would interact with real Redis, which is not ideal for specs
    end
  {% end %}
end

# Helper methods for creating contexts in specs
private def build_context
  request = HTTP::Request.new("GET", "/")
  response = HTTP::Server::Response.new(IO::Memory.new)
  HTTP::Server::Context.new(request, response)
end
