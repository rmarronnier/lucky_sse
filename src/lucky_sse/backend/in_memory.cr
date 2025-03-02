# In-memory backend for client management
module Lucky::SSE
  class InMemoryBackend < Backend
    getter clients = [] of Stream

    def add_client(stream : Stream)
      @clients << stream
    end

    def remove_client(stream : Stream)
      @clients.delete(stream)
    end

    def broadcast(event : String, data : String, id : String? = nil, filter : Hash(String, String)? = nil)
      matched_clients = 0

      @clients.each do |client|
        # Skip if filter doesn't match
        if filter && !client.matches?(filter)
          next
        end

        begin
          client.send(data: data, event: event, id: id || Random::Secure.hex(8))
          matched_clients += 1
        rescue SSEDisconnectError
          # Will be cleaned up in the next cycle
        end
      end

      matched_clients
    end

    def client_count : Int32
      @clients.size
    end

    def cleanup_disconnected_clients
      @clients.reject! { |client| client.response.closed? }
    end
  end
end
