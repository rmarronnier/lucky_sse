module Lucky::SSE::Writer
  def self.write_comment(response : HTTP::Server::Response, text : String) : Nil
    response.print ": #{text}\n\n"
    response.flush
  end

  def self.write_event(response : HTTP::Server::Response, event : Lucky::SSE::Event) : Nil
    event.id.try do |id|
      sanitized = sanitize_field_value(id)
      response.print "id: #{sanitized}\n" unless sanitized.empty?
    end

    event_name = sanitize_field_value(event.name)
    event_name = "message" if event_name.empty?
    response.print "event: #{event_name}\n"

    event.retry_ms.try do |retry_ms|
      response.print "retry: #{retry_ms}\n" if retry_ms >= 0
    end

    event.data.split('\n').each do |line|
      response.print "data: #{line}\n"
    end

    response.print "\n"
    response.flush
  end

  private def self.sanitize_field_value(value : String) : String
    value.delete('\0').delete('\r').delete('\n')
  end
end
