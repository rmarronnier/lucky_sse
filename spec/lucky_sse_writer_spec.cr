require "./spec_helper"

describe Lucky::SSE::Writer do
  it "sanitizes id and event fields to prevent SSE frame injection" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)

    event = Lucky::SSE::Event.new(
      id: "abc\nretry: 999\r\u0000",
      name: "order\nid: injected\r",
      data: "line1\nline2"
    )

    Lucky::SSE::Writer.write_event(response, event)
    response.close
    output = io.to_s

    output.should contain("id: abcretry: 999\n")
    output.should contain("event: orderid: injected\n")
    output.should contain("data: line1\n")
    output.should contain("data: line2\n")
    output.should_not contain("event: order\nid: injected\n")
    output.should_not contain("id: abc\nretry: 999")
  end

  it "falls back to message when sanitized event name is empty" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    event = Lucky::SSE::Event.new(id: "evt-1", name: "\n\r\u0000", data: "ok")

    Lucky::SSE::Writer.write_event(response, event)
    response.close
    io.to_s.should contain("event: message\n")
  end

  it "omits negative retry values" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    event = Lucky::SSE::Event.new(id: "evt-1", name: "tick", data: "ok", retry_ms: -1)

    Lucky::SSE::Writer.write_event(response, event)
    response.close
    io.to_s.should_not contain("\nretry: -1\n")
  end
end
