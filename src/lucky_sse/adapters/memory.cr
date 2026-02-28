class Lucky::SSE::Adapters::Memory < Lucky::SSE::Adapter
  @listeners = Hash(String, Set(Channel(String))).new { |hash, key| hash[key] = Set(Channel(String)).new }
  @lock = Mutex.new

  private class MemorySubscription < Lucky::SSE::Subscription
    def initialize(@topic : String, @channel : Channel(String), @adapter : Lucky::SSE::Adapters::Memory)
    end

    def close : Nil
      @adapter.unsubscribe(@topic, @channel)
      begin
        @channel.close
      rescue
      end
    end
  end

  def publish(topic : String, payload : String) : Nil
    listeners = @lock.synchronize { @listeners[topic].dup }
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

    spawn do
      loop do
        payload = channel.receive
        block.call(payload)
      end
    rescue Channel::ClosedError
      # Normal subscription close path.
    end

    MemorySubscription.new(topic, channel, self)
  end

  protected def unsubscribe(topic : String, channel : Channel(String)) : Nil
    @lock.synchronize do
      listeners = @listeners[topic]
      listeners.delete(channel)
      @listeners.delete(topic) if listeners.empty?
    end
  end
end
