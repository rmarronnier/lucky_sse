require "./spec_helper"

describe Lucky::SSE::Stream do
  it "accepts all events by default" do
    stream = Lucky::SSE::Stream.new("orders")
    event = Lucky::SSE::ParsedEvent.new(
      id: nil,
      name: "anything",
      data_raw: "{}",
      data_json: nil,
      envelope_json: nil
    )

    stream.accepts?(event).should be_true
  end

  it "restricts accepted events when allow_events is set" do
    stream = Lucky::SSE::Stream.new("orders").allow_events("created", "updated")

    created = Lucky::SSE::ParsedEvent.new(
      id: "1",
      name: "created",
      data_raw: "{}",
      data_json: nil,
      envelope_json: nil
    )
    deleted = Lucky::SSE::ParsedEvent.new(
      id: "2",
      name: "deleted",
      data_raw: "{}",
      data_json: nil,
      envelope_json: nil
    )

    stream.accepts?(created).should be_true
    stream.accepts?(deleted).should be_false
  end

  it "applies custom filters after event name filtering" do
    stream = Lucky::SSE::Stream.new("orders")
      .allow_events("updated")
      .filter { |event| event.data_json.try(&.as_h["tenant"]?.try(&.as_s)) == "acme" }

    accepted = Lucky::SSE::ParsedEvent.new(
      id: "1",
      name: "updated",
      data_raw: %({"tenant":"acme"}),
      data_json: JSON.parse(%({"tenant":"acme"})),
      envelope_json: nil
    )
    rejected = Lucky::SSE::ParsedEvent.new(
      id: "2",
      name: "updated",
      data_raw: %({"tenant":"other"}),
      data_json: JSON.parse(%({"tenant":"other"})),
      envelope_json: nil
    )

    stream.accepts?(accepted).should be_true
    stream.accepts?(rejected).should be_false
  end
end
