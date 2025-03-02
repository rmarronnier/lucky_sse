require "./spec_helper"

# Mock Lucky action for testing
abstract class MockAction
  include Lucky::SSE::Handler

  getter context : HTTP::Server::Context

  def initialize
    request = HTTP::Request.new("GET", "/")
    response = HTTP::Server::Response.new(IO::Memory.new)
    @context = HTTP::Server::Context.new(request, response)
  end

  # Stub methods required for Handler
  def params
    MockParams.new
  end

  # Mock sse macro that can be called in tests
  macro define_sse(path = "/events")
    sse {{ path }}
  end
end

# Mock params for testing
class MockParams
  def get(key : String)
    case key
    when "message"
      "test message"
    when "event_type"
      "test_event"
    else
      ""
    end
  end

  def get?(key : String)
    case key
    when "id"
      "test123"
    else
      nil
    end
  end
end

describe "Lucky::SSE::Handler integration" do
  describe "#sse_stream" do
    it "creates a stream and registers it" do
      action = MockAction.new

      # Capture client counts before and after
      before_count = Lucky::SSE::Handler.client_count

      # Create the stream
      stream = action.sse_stream

      # Verify it was registered
      Lucky::SSE::Handler.client_count.should eq(before_count + 1)

      # Clean up
      Lucky::SSE::Handler.cleanup_disconnected_clients
    end

    it "accepts metadata" do
      action = MockAction.new

      # Create the stream with metadata
      metadata = {"channel" => "test", "user" => "123"}
      stream = action.sse_stream(metadata: metadata)

      # Verify metadata was set
      stream.get_metadata("channel").should eq("test")
      stream.get_metadata("user").should eq("123")

      # Clean up
      Lucky::SSE::Handler.cleanup_disconnected_clients
    end

    it "sets up heartbeat" do
      action = MockAction.new

      # Create a stream with a very short heartbeat interval
      # In a real test, we'd use timecop or similar to avoid actual waiting
      stream = action.sse_stream(heartbeat_interval: 0.01)

      # Capture output
      output = IO::Memory.new
      allow(action.context.response.output).to receive(:print).and_return { |message| output << message }
      allow(action.context.response.output).to receive(:flush)

      # Wait for at least one heartbeat
      sleep 0.02

      # Verify heartbeat was sent
      output.to_s.should contain(": heartbeat")

      # Clean up
      Lucky::SSE::Handler.cleanup_disconnected_clients
    end
  end

  describe ".broadcast_event" do
    it "sends to all clients" do
      # Create some test streams
      action1 = MockAction.new
      action2 = MockAction.new
      stream1 = action1.sse_stream
      stream2 = action2.sse_stream

      # Capture outputs
      output1 = IO::Memory.new
      output2 = IO::Memory.new
      allow(action1.context.response.output).to receive(:print).and_return { |message| output1 << message }
      allow(action2.context.response.output).to receive(:print).and_return { |message| output2 << message }
      allow(action1.context.response.output).to receive(:flush)
      allow(action2.context.response.output).to receive(:flush)

      # Broadcast an event
      Lucky::SSE::Handler.broadcast_event("test_event", "hello world")

      # Verify both received it
      output1.to_s.should contain("event: test_event")
      output1.to_s.should contain("data: hello world")
      output2.to_s.should contain("event: test_event")
      output2.to_s.should contain("data: hello world")

      # Clean up
      Lucky::SSE::Handler.cleanup_disconnected_clients
    end

    it "filters by metadata" do
      # Create test streams with different metadata
      action1 = MockAction.new
      action2 = MockAction.new
      stream1 = action1.sse_stream(metadata: {"channel" => "news"})
      stream2 = action2.sse_stream(metadata: {"channel" => "sports"})

      # Capture outputs
      output1 = IO::Memory.new
      output2 = IO::Memory.new
      allow(action1.context.response.output).to receive(:print).and_return { |message| output1 << message }
      allow(action2.context.response.output).to receive(:print).and_return { |message| output2 << message }
      allow(action1.context.response.output).to receive(:flush)
      allow(action2.context.response.output).to receive(:flush)

      # Broadcast only to news channel
      Lucky::SSE::Handler.broadcast_event(
        "update",
        "breaking news",
        filter: {"channel" => "news"}
      )

      # Verify only news channel received it
      output1.to_s.should contain("event: update")
      output1.to_s.should contain("data: breaking news")
      output2.to_s.should be_empty

      # Clean up
      Lucky::SSE::Handler.cleanup_disconnected_clients
    end
  end

  # describe "sse macro" do
  #   it "can be defined in an action" do
  #     # Define a test action with the sse macro
  #     class TestAction < MockAction
  #       define_sse
  #     end

  #     # The macro doesn't execute in specs, we're just testing that it compiles
  #     typeof(TestAction).should eq(TestAction.class)
  #   end
  # end
end
