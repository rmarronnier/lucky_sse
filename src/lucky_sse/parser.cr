module Lucky::SSE::Parser
  def self.parse(payload : String) : Lucky::SSE::ParsedEvent
    parsed = begin
      JSON.parse(payload)
    rescue JSON::ParseException
      nil
    end

    if parsed
      if body = parsed.as_h?
        event_name = body["event"]?.try(&.as_s?) || "message"
        event_id = body["id"]?.try(&.as_s?)
        data_json = body["data"]?
        data_raw = data_json ? data_json.to_json : payload
        return Lucky::SSE::ParsedEvent.new(
          id: event_id,
          name: event_name,
          data_raw: data_raw,
          data_json: data_json,
          envelope_json: parsed
        )
      end

      return Lucky::SSE::ParsedEvent.new(
        id: nil,
        name: "message",
        data_raw: payload,
        data_json: parsed,
        envelope_json: nil
      )
    end

    Lucky::SSE::ParsedEvent.new(
      id: nil,
      name: "message",
      data_raw: payload,
      data_json: nil,
      envelope_json: nil
    )
  end
end
