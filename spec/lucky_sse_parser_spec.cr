require "./spec_helper"

describe Lucky::SSE::Parser do
  it "parses Lucky envelope payloads" do
    payload = {
      id:          "evt-1",
      event:       "order.updated",
      occurred_at: "2026-02-28T22:00:00Z",
      meta:        {"topic" => "orders"},
      data:        {"id" => 12, "status" => "paid"},
    }.to_json

    parsed = Lucky::SSE::Parser.parse(payload)
    parsed.id.should eq("evt-1")
    parsed.name.should eq("order.updated")
    parsed.data_json.not_nil!.as_h["id"].as_i.should eq(12)
    parsed.envelope_json.not_nil!.as_h["event"].as_s.should eq("order.updated")
    parsed.data_raw.should eq(%({"id":12,"status":"paid"}))
  end

  it "treats envelope-like payload without event name as plain message payload" do
    payload = {
      id:          "evt-2",
      occurred_at: "2026-02-28T22:00:00Z",
      meta:        {"topic" => "orders"},
      data:        {"ok" => true},
    }.to_json

    parsed = Lucky::SSE::Parser.parse(payload)
    parsed.id.should be_nil
    parsed.name.should eq("message")
    parsed.data_json.not_nil!.as_h["id"].as_s.should eq("evt-2")
    parsed.data_json.not_nil!.as_h["data"].as_h["ok"].as_bool.should be_true
  end

  it "parses non-envelope JSON as message data" do
    parsed = Lucky::SSE::Parser.parse(%({"k":"v"}))
    parsed.id.should be_nil
    parsed.name.should eq("message")
    parsed.data_json.not_nil!.as_h["k"].as_s.should eq("v")
    parsed.envelope_json.should be_nil
    parsed.data_raw.should eq(%({"k":"v"}))
  end

  it "does not misclassify payloads that only include data as envelopes" do
    payload = {
      "status" => "accepted",
      "data"   => {"id" => 10},
    }.to_json

    parsed = Lucky::SSE::Parser.parse(payload)
    parsed.id.should be_nil
    parsed.name.should eq("message")
    parsed.envelope_json.should be_nil
    parsed.data_json.not_nil!.as_h["status"].as_s.should eq("accepted")
    parsed.data_json.not_nil!.as_h["data"].as_h["id"].as_i.should eq(10)
  end

  it "does not treat event+data objects as envelope without envelope markers" do
    payload = {
      "event" => "domain.custom",
      "data"  => {"keep" => "whole-object"},
      "extra" => "still-there",
    }.to_json

    parsed = Lucky::SSE::Parser.parse(payload)
    parsed.name.should eq("message")
    parsed.envelope_json.should be_nil
    parsed.data_json.not_nil!.as_h["event"].as_s.should eq("domain.custom")
    parsed.data_json.not_nil!.as_h["extra"].as_s.should eq("still-there")
  end

  it "returns raw payload when data is not JSON" do
    parsed = Lucky::SSE::Parser.parse("raw-text")
    parsed.id.should be_nil
    parsed.name.should eq("message")
    parsed.data_json.should be_nil
    parsed.envelope_json.should be_nil
    parsed.data_raw.should eq("raw-text")
  end
end
