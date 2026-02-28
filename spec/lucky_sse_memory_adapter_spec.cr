require "./spec_helper"

describe Lucky::SSE::Adapters::Memory do
  it "delivers published payloads to subscribers" do
    adapter = Lucky::SSE::Adapters::Memory.new
    received = Channel(String).new(1)
    subscription = adapter.subscribe("orders") { |payload| received.send(payload) }

    begin
      adapter.publish("orders", "hello")
      select
      when payload = received.receive
        payload.should eq("hello")
      when timeout(500.milliseconds)
        fail "expected published payload to be received"
      end
    ensure
      subscription.close
    end
  end

  it "does not block publishers when a subscriber callback raises" do
    adapter = Lucky::SSE::Adapters::Memory.new
    subscription = adapter.subscribe("orders") { |_payload| raise "boom" }
    done = Channel(Nil).new(1)

    begin
      spawn do
        256.times { |index| adapter.publish("orders", index.to_s) }
        done.send(nil)
      end

      select
      when done.receive
      when timeout(1.second)
        fail "publishing should not block when subscriber callback raises"
      end
    ensure
      subscription.close
    end
  end

  it "removes closed subscriptions so future publishes stay non-blocking" do
    adapter = Lucky::SSE::Adapters::Memory.new
    subscription = adapter.subscribe("orders") { |_payload| }
    subscription.close
    done = Channel(Nil).new(1)

    spawn do
      512.times { |index| adapter.publish("orders", "m#{index}") }
      done.send(nil)
    end

    select
    when done.receive
    when timeout(1.second)
      fail "publishing should remain non-blocking after subscription close"
    end
  end
end
