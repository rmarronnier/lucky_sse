module Lucky::SSE::Writer
  def self.write_comment(response : HTTP::Server::Response, text : String) : Nil
    response.print ": #{text}\n\n"
    response.flush
  end

  def self.write_event(response : HTTP::Server::Response, event : Lucky::SSE::Event) : Nil
    event.id.try { |id| response.print "id: #{id}\n" }
    response.print "event: #{event.name}\n"
    event.retry_ms.try { |retry_ms| response.print "retry: #{retry_ms}\n" }

    event.data.split('\n').each do |line|
      response.print "data: #{line}\n"
    end

    response.print "\n"
    response.flush
  end
end
