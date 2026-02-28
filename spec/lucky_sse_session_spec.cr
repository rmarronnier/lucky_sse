require "./spec_helper"

private def wait_for_connected_output(io : IO::Memory) : Nil
  connected = wait_until(1.second) { io.to_s.includes?(": connected") }
  fail "session did not start in time" unless connected
end

describe Lucky::SSE::Session do
  it "streams accepted events and exits when response closes" do
    adapter = Lucky::SSE::Adapters::Memory.new
    stream = Lucky::SSE::Stream.new("orders").allow_events("order.updated")
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    session = Lucky::SSE::Session.new(
      response,
      stream,
      adapter: adapter,
      heartbeat_interval: 10.milliseconds
    )

    finished = Channel(Nil).new(1)
    spawn do
      session.run
      finished.send(nil)
    end

    wait_for_connected_output(io)
    adapter.publish("orders", {
      id:          "evt-ignore",
      event:       "order.created",
      occurred_at: "2026-02-28T22:00:00Z",
      meta:        {"topic" => "orders"},
      data:        {"id" => 1},
    }.to_json)
    adapter.publish("orders", {
      id:          "evt-1",
      event:       "order.updated",
      occurred_at: "2026-02-28T22:00:00Z",
      meta:        {"topic" => "orders"},
      data:        {"id" => 1},
    }.to_json)

    wait_until(1.second) { io.to_s.includes?("event: order.updated\n") }.should be_true

    response.close

    select
    when finished.receive
    when timeout(1.second)
      fail "session should finish after response closes"
    end

    output = io.to_s
    output.should contain(": connected")
    output.should contain("event: order.updated\n")
    output.should_not contain("event: order.created\n")
  end
end
