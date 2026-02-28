require "./spec_helper"

redis_url = ENV["LUCKY_SSE_REDIS_URL"]?

if redis_url
  describe Lucky::SSE::Adapters::Redis do
    it "publishes and receives payloads (integration)" do
      adapter = Lucky::SSE::Adapters::Redis.new(redis_url)
      topic = "lucky_sse_spec_#{UUID.random}"
      received = Channel(String).new(1)
      subscription = adapter.subscribe(topic) { |payload| received.send(payload) }
      payload = {id: "evt-1", event: "spec.message", data: {"ok" => true}}.to_json

      begin
        sleep 50.milliseconds
        adapter.publish(topic, payload)

        select
        when actual = received.receive
          actual.should eq(payload)
        when timeout(2.seconds)
          fail "did not receive redis message in time"
        end
      ensure
        subscription.close
      end
    end

    it "keeps subscription alive when callback raises (integration)" do
      adapter = Lucky::SSE::Adapters::Redis.new(redis_url)
      topic = "lucky_sse_spec_#{UUID.random}"
      received = Channel(String).new(1)
      callback_calls = Atomic(Int32).new(0)

      subscription = adapter.subscribe(topic) do |payload|
        call = callback_calls.add(1)
        if call == 1
          raise "boom"
        else
          received.send(payload)
        end
      end

      first = {id: "evt-raise", event: "spec.message", data: {"n" => 1}}.to_json
      second = {id: "evt-ok", event: "spec.message", data: {"n" => 2}}.to_json

      begin
        sleep 50.milliseconds
        adapter.publish(topic, first)
        adapter.publish(topic, second)

        select
        when actual = received.receive
          actual.should eq(second)
          callback_calls.get.should be >= 2
        when timeout(2.seconds)
          fail "did not receive message after callback raise"
        end
      ensure
        subscription.close
      end
    end
  end
else
  describe Lucky::SSE::Adapters::Redis do
    it "has optional integration coverage disabled by default" do
      redis_url.should be_nil
    end
  end
end
