require "./spec_helper"

private class DummySubscription < Lucky::SSE::Subscription
  def close : Nil
  end
end

private class CaptureAdapter < Lucky::SSE::Adapter
  getter messages = [] of NamedTuple(topic: String, payload: String)

  def publish(topic : String, payload : String) : Nil
    @messages << {topic: topic, payload: payload}
  end

  def subscribe(topic : String, &block : String -> Nil) : Lucky::SSE::Subscription
    DummySubscription.new
  end
end

describe Lucky::SSE do
  it "publishes envelope payloads with reserved metadata enforced" do
    settings = Lucky::SSE.settings
    previous_adapter = settings.adapter
    previous_producer = settings.default_producer
    adapter = CaptureAdapter.new

    begin
      settings.adapter = adapter
      settings.default_producer = "orders_app"

      envelope_id = Lucky::SSE.publish(
        "orders",
        "order.created",
        {"order_id" => 42},
        meta: {
          "topic"    => "wrong-topic",
          "producer" => "wrong-producer",
          "trace_id" => "wrong-trace",
          "tenant"   => "acme",
        },
        id: "evt-1",
        occurred_at: Time.utc(2026, 2, 1, 0, 0, 0)
      )

      envelope_id.should eq("evt-1")
      adapter.messages.size.should eq(1)

      message = adapter.messages.first
      message[:topic].should eq("orders")

      json = JSON.parse(message[:payload]).as_h
      json["id"].as_s.should eq("evt-1")
      json["event"].as_s.should eq("order.created")
      json["occurred_at"].as_s.should eq("2026-02-01T00:00:00Z")
      json["data"].as_h["order_id"].as_i.should eq(42)

      meta = json["meta"].as_h
      meta["topic"].as_s.should eq("orders")
      meta["producer"].as_s.should eq("orders_app")
      meta["trace_id"].as_s.should eq("evt-1")
      meta["tenant"].as_s.should eq("acme")
    ensure
      settings.adapter = previous_adapter
      settings.default_producer = previous_producer
    end
  end

  it "publish_raw parses JSON payloads and falls back to string when invalid" do
    settings = Lucky::SSE.settings
    previous_adapter = settings.adapter
    adapter = CaptureAdapter.new

    begin
      settings.adapter = adapter

      Lucky::SSE.publish_raw("chat", "message", %({"text":"hello"}), id: "evt-json")
      Lucky::SSE.publish_raw("chat", "message", "plain-text", id: "evt-string")

      adapter.messages.size.should eq(2)

      first = JSON.parse(adapter.messages[0][:payload]).as_h
      first["data"].as_h["text"].as_s.should eq("hello")

      second = JSON.parse(adapter.messages[1][:payload]).as_h
      second["data"].as_s.should eq("plain-text")
    ensure
      settings.adapter = previous_adapter
    end
  end

  it "publish_unwrapped sends payload directly without envelope wrapping" do
    settings = Lucky::SSE.settings
    previous_adapter = settings.adapter
    adapter = CaptureAdapter.new

    begin
      settings.adapter = adapter
      Lucky::SSE.publish_unwrapped("raw_topic", %({"native":"payload"}))

      adapter.messages.size.should eq(1)
      adapter.messages.first[:topic].should eq("raw_topic")
      adapter.messages.first[:payload].should eq(%({"native":"payload"}))
    ensure
      settings.adapter = previous_adapter
    end
  end
end
