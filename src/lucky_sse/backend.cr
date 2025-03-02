module Lucky::SSE
  # Abstract backend for client management
  abstract class Backend
    abstract def add_client(stream : Stream)
    abstract def remove_client(stream : Stream)
    abstract def broadcast(event : String, data : String, id : String?, filter : Hash(String, String)?)
    abstract def client_count : Int32
    abstract def cleanup_disconnected_clients
  end
end

require "./backend"
