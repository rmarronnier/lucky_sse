# A class to help manage SSE connections and events
module Lucky::SSE
  class Stream
    # Default headers for SSE responses
    DEFAULT_HEADERS = {
      "Content-Type"  => "text/event-stream",
      "Cache-Control" => "no-cache",
      "Connection"    => "keep-alive",
    }

    getter context : HTTP::Server::Context
    getter response : HTTP::Server::Response
    getter io : IO
    getter id : String
    getter metadata : Hash(String, String)

    def initialize(@context, headers : HTTP::Headers? = nil, @metadata = {} of String => String)
      @response = context.response
      @io = @response.output
      @id = Random::Secure.hex(16) # Unique ID for this stream

      # Set SSE headers
      DEFAULT_HEADERS.each do |key, value|
        @response.headers[key] = value
      end

      # Add any custom headers
      headers.try &.each do |key, value|
        @response.headers[key] = value
      end

      # Disable response buffering for immediate writes
      @response.flush
    end

    # Send an SSE event with an event type and data
    def send(data, event : String? = nil, id : String? = nil, retry_ms : Int32? = nil) : Nil
      message = String.build do |io|
        io << "event: #{event}\n" if event
        io << "id: #{id}\n" if id
        io << "retry: #{retry_ms}\n" if retry_ms

        # Handle multiline data by prefixing each line with "data: "
        data.to_s.each_line do |line|
          io << "data: #{line}\n"
        end

        # End the event with an additional newline
        io << "\n"
      end

      # Write message to the response stream
      @io.print(message)
      @io.flush
    rescue IO::Error
      # Handle disconnection
      raise SSEDisconnectError.new("Client disconnected")
    end

    # Send a keep-alive comment to prevent connection timeout
    def heartbeat : Nil
      @io.print(": heartbeat\n\n")
      @io.flush
    rescue IO::Error
      # Handle disconnection
      raise SSEDisconnectError.new("Client disconnected during heartbeat")
    end

    # Close the SSE stream
    def close : Nil
      @io.close
    end

    # Set a metadata value for filtering
    def set_metadata(key : String, value : String)
      @metadata[key] = value
    end

    # Get a metadata value
    def get_metadata(key : String) : String?
      @metadata[key]?
    end

    # Check if this stream matches metadata criteria
    def matches?(criteria : Hash(String, String)) : Bool
      criteria.all? do |key, value|
        @metadata[key]? == value
      end
    end
  end

  # Error raised when an SSE connection is closed unexpectedly
  class SSEDisconnectError < Exception
  end
end
