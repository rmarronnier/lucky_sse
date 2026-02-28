abstract class Lucky::SSE::Adapter
  abstract def publish(topic : String, payload : String) : Nil
  abstract def subscribe(topic : String, &block : String -> Nil) : Lucky::SSE::Subscription
end
