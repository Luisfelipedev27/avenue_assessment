require "rails_helper"

RSpec.describe Nominatim::Client do
  let(:gate) { Nominatim::RequestGate.new }

  it "searches a US address without credentials and identifies the application" do
    http = stub_http_response("nominatim.openstreetmap.org", body: JSON.generate(api_fixture("nominatim")))
    result = described_class.new(request_gate: gate).geocode(address: "350 5th Ave, New York")

    expect(result.first.fetch("address").fetch("postcode")).to eq("10118")
    expect(http).to have_received(:request) do |request|
      expect(request.uri.path).to eq("/search")
      expect(request["User-Agent"]).to eq("AvenueWeather/1.0")
      expect(URI.decode_www_form(request.uri.query).to_h).to eq(
        "q" => "350 5th Ave, New York", "format" => "jsonv2",
        "addressdetails" => "1", "countrycodes" => "us", "limit" => "2"
      )
    end
  end

  it "allows switching the endpoint without changing the code" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NOMINATIM_URL", anything).and_return("https://geocoder.example.com/search")
    stub_http_response("geocoder.example.com", body: "[]")

    expect(described_class.new(request_gate: gate).geocode(address: "New York")).to eq([])
  end

  it "shares the request limit between client instances" do
    stub_const("Nominatim::Client::REQUEST_GATE", gate)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0)
    http = stub_http_response("nominatim.openstreetmap.org", body: "[]")
    described_class.new.geocode(address: "New York")

    expect { described_class.new.geocode(address: "Boston") }.to raise_error(Nominatim::RequestGate::Busy)
    expect(http).to have_received(:request).once
  end
end
