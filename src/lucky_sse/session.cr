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
    subscription : Lucky::SSE::Subscription? = nil
    closed = Channel(Nil).new(1)
    stop_heartbeat : Channel(Nil)? = Channel(Nil).new(1)
    closed_flag = Atomic(Bool).new(false)

    signal_closed = -> do
      return if closed_flag.swap(true)
      begin
        closed.send(nil)
      rescue
      end
      nil
  rescue
    nil
    end

    prepare_response

    subscription = @adapter.subscribe(@stream.topic) do |payload|
      parsed = Lucky::SSE::Parser.parse(payload)
      next unless @stream.accepts?(parsed)

      begin
        write_event(parsed.id, parsed.name, parsed.data_raw)
      rescue
        signal_closed.call
      end
    end

    spawn do
      begin
        loop do
          select
          when stop_heartbeat.not_nil!.receive
            break
          when timeout(@heartbeat_interval)
            write_comment("ping")
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

    write_comment("connected")
  end

  private def write_event(id : String?, name : String, data : String) : Nil
    @write_lock.synchronize do
      Lucky::SSE::Writer.write_event(
        @response,
        Lucky::SSE::Event.new(id: id, name: name, data: data)
      )
    end
  end

  private def write_comment(text : String) : Nil
    @write_lock.synchronize do
      Lucky::SSE::Writer.write_comment(@response, text)
    end
  end
end
