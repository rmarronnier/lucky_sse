class Lucky::SSE::Adapters::Redis < Lucky::SSE::Adapter
  private class RedisSubscription < Lucky::SSE::Subscription
    def initialize
      @closed = Atomic(Bool).new(false)
      @lock = Mutex.new
      @redis = nil.as(::Redis::Client?)
    end

    def close : Nil
      return if @closed.swap(true)

      redis = @lock.synchronize do
        client = @redis
        @redis = nil
        client
      end

      begin
        redis.try(&.close)
      rescue
      end
    end

    def closed? : Bool
      @closed.get
    end

    def bind(redis : ::Redis::Client) : Nil
      close_now = false
      @lock.synchronize do
        if @closed.get
          close_now = true
        else
          @redis = redis
        end
      end

      return unless close_now
      begin
        redis.close
      rescue
      end
    end

    def unbind(redis : ::Redis::Client) : Nil
      @lock.synchronize do
        @redis = nil if @redis == redis
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
    subscription = RedisSubscription.new

    spawn do
      backoff = 100.milliseconds
      max_backoff = 5.seconds

      until subscription.closed?
        redis = ::Redis::Client.new(URI.parse(@url))
        subscription.bind(redis)

        begin
          redis.subscribe(topic) do |listener, _connection|
            listener.on_message do |_channel, payload|
              begin
                block.call(payload)
              rescue
                # Keep subscriber callback failures isolated so the
                # subscription connection stays healthy.
              end
            end
          end
          backoff = 100.milliseconds
        rescue
          break if subscription.closed?
          sleep(backoff)
          doubled = backoff * 2
          backoff = doubled > max_backoff ? max_backoff : doubled
        ensure
          subscription.unbind(redis)
          begin
            redis.close
          rescue
          end
        end
      end
    end

    subscription
  end
end
