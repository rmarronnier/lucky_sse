class Lucky::SSE::Stream
  getter topic : String

  @allowed_events : Set(String)?
  @filters : Array(Proc(Lucky::SSE::ParsedEvent, Bool))

  def initialize(@topic : String)
    @allowed_events = nil
    @filters = [] of Proc(Lucky::SSE::ParsedEvent, Bool)
  end

  def allow_events(*event_names : String) : self
    @allowed_events ||= Set(String).new
    event_names.each { |name| @allowed_events.not_nil!.add(name) }
    self
  end

  def filter(&block : Lucky::SSE::ParsedEvent -> Bool) : self
    @filters << block
    self
  end

  def accepts?(event : Lucky::SSE::ParsedEvent) : Bool
    allowed = @allowed_events
    if allowed && !allowed.includes?(event.name)
      return false
    end

    @filters.all? { |rule| rule.call(event) }
  end
end
