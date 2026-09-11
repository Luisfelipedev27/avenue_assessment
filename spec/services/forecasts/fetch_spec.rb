require "rails_helper"

RSpec.describe Forecasts::Fetch do
  let(:client) { instance_double(OpenMeteo::Client, forecast: payload) }
  let(:payload) { api_fixture("open_meteo") }
  let(:location) { { address: "350 5th Ave, New York, NY 10118", postal_code: "10118", country: "US", latitude: 40.7484421, longitude: -73.9856589 } }
  let(:resolved) { instance_double(Addresses::Resolve, success?: true, location: location) }
  let(:resolver) { class_double(Addresses::Resolve, call: resolved) }

  def fetch
    described_class.call(address: "350 5th Ave, New York", address_resolver: resolver, client: client)
  end

  it "returns current, high and low temperatures with units and observation time" do
    service = fetch

    expect(service).to be_success
    expect(service.location).to eq(location)
    expect(service.forecast).to eq(
      temperature: 72.5, high: 78.8, low: 64.4, unit: "F", updated_at: 1789063200
    )
    expect(resolver).to have_received(:call).with(address: "350 5th Ave, New York")
    expect(client).to have_received(:forecast).with(latitude: 40.7484421, longitude: -73.9856589)
  end

  it "stops when address resolution fails" do
    allow(resolved).to receive_messages(success?: false, error_message: "Address not found")

    service = fetch
    expect(service).not_to be_success
    expect(service.error_message).to eq("Address not found")
    expect(service.forecast).to be_nil
    expect(client).not_to have_received(:forecast)
  end

  it "supports zero and negative temperatures" do
    payload["current"]["temperature_2m"] = 0
    payload["daily"] = { "temperature_2m_max" => [ 0 ], "temperature_2m_min" => [ -10 ] }

    expect(fetch).to be_success
  end

  [ nil, "72.5" ].each do |temperature|
    it "rejects invalid temperatures: #{temperature.inspect}" do
      payload["current"]["temperature_2m"] = temperature

      service = fetch
      expect(service).not_to be_success
      expect(service.forecast).to be_nil
    end
  end

  it "rejects a missing timestamp" do
    payload["current"].delete("time")

    expect(fetch).not_to be_success
  end

  it "rejects an inverted temperature range" do
    payload["daily"]["temperature_2m_min"] = [ 100 ]

    expect(fetch).not_to be_success
  end

  [ nil, {}, { "temperature_2m_max" => [] }, { "temperature_2m_max" => [ nil ], "temperature_2m_min" => [ 0 ] } ].each do |forecast|
    it "handles malformed forecast data: #{forecast.inspect}" do
      payload["daily"] = forecast

      service = fetch
      expect(service.error_message).to eq("Unable to retrieve the forecast right now")
      expect(service.forecast).to be_nil
    end
  end

  [ ExternalApis::JsonClient::Unavailable, ExternalApis::JsonClient::InvalidResponse ].each do |error|
    it "handles #{error}" do
      allow(client).to receive(:forecast).and_raise(error)

      expect(fetch.error_message).to eq("Unable to retrieve the forecast right now")
    end
  end

  it "returns a service failure when the weather provider sends malformed HTTP" do
    http = stub_http_response("api.open-meteo.com", body: "")
    allow(http).to receive(:request).and_raise(Net::HTTPBadResponse, "invalid status line")

    service = described_class.call(
      address: "350 5th Ave, New York", address_resolver: resolver, client: OpenMeteo::Client.new
    )

    expect(service).not_to be_success
    expect(service.forecast).to be_nil
    expect(service.error_message).to eq("Unable to retrieve the forecast right now")
  end

  it "integrates the address and weather clients using simulated HTTP responses" do
    stub_http_response("nominatim.openstreetmap.org", body: JSON.generate(api_fixture("nominatim")))
    http = stub_http_response("api.open-meteo.com", body: JSON.generate(payload))

    service = described_class.call(address: "350 5th Ave, New York")

    expect(service).to be_success
    expect(service.location[:postal_code]).to eq("10118")
    expect(service.forecast[:temperature]).to eq(72.5)
    expect(http).to have_received(:request) do |request|
      expect(URI.decode_www_form(request.uri.query).to_h).to include(
        "latitude" => "40.7484421", "longitude" => "-73.9856589"
      )
    end
  end
end
