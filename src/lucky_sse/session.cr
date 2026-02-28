class Lucky::SSE::Session
  def initialize(
    @response : HTTP::Server::Response,
    @stream : Lucky::SSE::Stream,
    @adapter : Lucky::SSE::Adapter = Lucky::SSE.settings.adapter,
    @heartbeat_interval : Time::Span = Lucky::SSE.settings.heartbeat_interval,
  )
    @write_lock = Mutex.new
  end

  def run : Nil
    prepare_response

    stop_heartbeat : Channel(Nil)? = nil
    subscription = @adapter.subscribe(@stream.topic) do |payload|
      parsed = Lucky::SSE::Parser.parse(payload)
      next unless @stream.accepts?(parsed)

      event = Lucky::SSE::Event.new(
        id: parsed.id,
        name: parsed.name,
        data: parsed.data_raw
      )

      safe_write { Lucky::SSE::Writer.write_event(@response, event) }
    end

    closed = Channel(Nil).new(1)
    stop_heartbeat = Channel(Nil).new(1)
    closed_flag = Atomic(Bool).new(false)

    signal_closed = -> do
      return if closed_flag.swap(true)
      closed.send(nil)
  rescue
    end

    spawn do
      begin
        loop do
          select
          when stop_heartbeat.receive
            break
          when timeout(@heartbeat_interval)
            safe_write { Lucky::SSE::Writer.write_comment(@response, "ping") }
          end
        end
      rescue
        signal_closed.call
      end
    end

    closed.receive
  ensure
    begin
      stop_heartbeat.try(&.send(nil))
    rescue
    end

    begin
      subscription.try(&.close)
    rescue
    end
  end

  private def prepare_response : Nil
    @response.headers["Content-Type"] = "text/event-stream"
    @response.headers["Cache-Control"] = "no-cache"
    @response.headers["Connection"] = "keep-alive"
    @response.headers["X-Accel-Buffering"] = "no"
    @response.status_code = 200
    @response.flush

    safe_write { Lucky::SSE::Writer.write_comment(@response, "connected") }
  end

  private def safe_write(&block : -> Nil) : Nil
    @write_lock.synchronize do
      block.call
    end
  end
end
