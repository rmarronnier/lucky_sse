class Lucky::SSE::Adapters::Memory < Lucky::SSE::Adapter
  @listeners = Hash(String, Set(Channel(String))).new { |hash, key| hash[key] = Set(Channel(String)).new }
  @lock = Mutex.new

  private class MemorySubscription < Lucky::SSE::Subscription
    def initialize(@topic : String, @channel : Channel(String), @adapter : Lucky::SSE::Adapters::Memory)
      @closed = Atomic(Bool).new(false)
    end

    def close : Nil
      return if @closed.swap(true)
      @adapter.unsubscribe(@topic, @channel)
      begin
        @channel.close
      rescue
      end
    end
  end

  def publish(topic : String, payload : String) : Nil
    listeners = @lock.synchronize do
      @listeners[topic]?.try(&.dup) || Set(Channel(String)).new
    end
    listeners.each do |channel|
      begin
        channel.send(payload)
      rescue Channel::ClosedError
      end
    end
  end

  def subscribe(topic : String, &block : String -> Nil) : Lucky::SSE::Subscription
    channel = Channel(String).new(128)
    @lock.synchronize { @listeners[topic].add(channel) }

    subscription = MemorySubscription.new(topic, channel, self)

    spawn do
      loop do
        payload = channel.receive
        begin
          block.call(payload)
        rescue
          # Subscriber callbacks are user code; keep the adapter healthy.
        end
      end
    rescue Channel::ClosedError
      # Normal subscription close path.
    ensure
      subscription.close
    end

    subscription
  end

  protected def unsubscribe(topic : String, channel : Channel(String)) : Nil
    @lock.synchronize do
      listeners = @listeners[topic]?
      return unless listeners
      listeners.delete(channel)
      @listeners.delete(topic) if listeners.empty?
    end
  end
end
