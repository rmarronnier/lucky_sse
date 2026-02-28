class Lucky::SSE::Adapters::Redis < Lucky::SSE::Adapter
  private class RedisSubscription < Lucky::SSE::Subscription
    def initialize(@redis : ::Redis::Client)
      @closed = Atomic(Bool).new(false)
    end

    def close : Nil
      return if @closed.swap(true)

      begin
        @redis.close
      rescue
      end
    end
  end

  def initialize(@url : String)
  end

  def publish(topic : String, payload : String) : Nil
    redis = ::Redis::Client.new(URI.parse(@url))
    redis.publish(topic, payload)
  ensure
    begin
      redis.close if redis
    rescue
    end
  end

  def subscribe(topic : String, &block : String -> Nil) : Lucky::SSE::Subscription
    redis = ::Redis::Client.new(URI.parse(@url))

    spawn do
      begin
        redis.subscribe(topic) do |subscription, _connection|
          subscription.on_message do |_channel, payload|
            block.call(payload)
          end
        end
      rescue
        # Normal close path for subscription fibers.
      ensure
        begin
          redis.close
        rescue
        end
      end
    end

    RedisSubscription.new(redis)
  end
end
