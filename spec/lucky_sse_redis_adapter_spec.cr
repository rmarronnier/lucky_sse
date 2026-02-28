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
  end
else
  describe Lucky::SSE::Adapters::Redis do
    it "has optional integration coverage disabled by default" do
      redis_url.should be_nil
    end
  end
end
