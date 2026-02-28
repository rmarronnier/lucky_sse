require "json"
require "uuid"
require "http/server/response"
require "redis"

require "./lucky_sse/version"
require "./lucky_sse/subscription"
require "./lucky_sse/adapter"
require "./lucky_sse/adapters"
require "./lucky_sse/event"
require "./lucky_sse/parsed_event"
require "./lucky_sse/parser"
require "./lucky_sse/writer"
require "./lucky_sse/stream"
require "./lucky_sse/configuration"
require "./lucky_sse/adapters/memory"
require "./lucky_sse/adapters/redis"
require "./lucky_sse/session"

module Lucky::SSE
  def self.configure(&)
    yield settings
  end

  def self.settings : Lucky::SSE::Configuration
    @@settings ||= Lucky::SSE::Configuration.new
  end

  def self.publish(topic : String, event : String, data, meta : Hash(String, String)? = nil, id : String? = nil, occurred_at : Time = Time.utc) : String
    envelope_id = id || UUID.random.to_s

    envelope_meta = {
      "topic"    => topic,
      "producer" => settings.default_producer,
      "trace_id" => envelope_id,
    }

    meta.try(&.each { |key, value| envelope_meta[key] = value })

    payload = {
      id:          envelope_id,
      event:       event,
      occurred_at: occurred_at.to_rfc3339,
      data:        data,
      meta:        envelope_meta,
    }.to_json

    settings.adapter.publish(topic, payload)
    envelope_id
  end

  def self.publish_raw(topic : String, event : String, raw : String, meta : Hash(String, String)? = nil, id : String? = nil, occurred_at : Time = Time.utc) : String
    parsed_data = begin
      JSON.parse(raw)
    rescue JSON::ParseException
      JSON::Any.new(raw)
    end

    publish(topic, event, parsed_data, meta: meta, id: id, occurred_at: occurred_at)
  end
end
