require "rails_helper"

RSpec.describe Addresses::Resolve do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:client) { instance_double(Nominatim::Client, geocode: api_fixture("nominatim")) }

  def resolve(address = "350 5th Ave, New York")
    described_class.call(address: address, client: client, cache: cache)
  end

  it "reuses a normalized address without consulting the provider" do
    first = resolve
    second = resolve(" 350  5TH Ave, NEW YORK ")

    expect(second).to be_success
    expect(second.location).to eq(first.location)
    expect(client).to have_received(:geocode).once
  end

  it "looks up different addresses independently" do
    resolve
    resolve("Another address")

    expect(client).to have_received(:geocode).twice
  end

  it "expires address results after 30 minutes" do
    travel_to(Time.zone.local(2026, 9, 11, 12)) do
      resolve
      travel 29.minutes
      resolve
      travel 1.minute + 1.second
      resolve

      expect(client).to have_received(:geocode).twice
    end
  end

  it "does not cache unresolved addresses" do
    allow(client).to receive(:geocode).and_return([])
    expect(resolve).not_to be_success
    allow(client).to receive(:geocode).and_return(api_fixture("nominatim"))

    expect(resolve).to be_success
    expect(client).to have_received(:geocode).twice
  end

  it "does not cache rate-limit errors" do
    allow(client).to receive(:geocode).and_raise(Nominatim::RequestGate::Busy)
    expect(resolve).not_to be_success
    allow(client).to receive(:geocode).and_return(api_fixture("nominatim"))

    expect(resolve).to be_success
    expect(client).to have_received(:geocode).twice
  end

  it "supports immediate repeated searches through the complete flow" do
    allow(Rails).to receive(:cache).and_return(cache)
    stub_const("Nominatim::Client::REQUEST_GATE", Nominatim::RequestGate.new)
    geocoder = stub_http_response("nominatim.openstreetmap.org", body: JSON.generate(api_fixture("nominatim")))
    weather = stub_http_response("api.open-meteo.com", body: JSON.generate(api_fixture("open_meteo")))

    first = Forecasts::Fetch.call(address: "350 5th Ave, New York")
    second = Forecasts::Fetch.call(address: "350 5th Ave, New York")

    expect(first).to be_success
    expect(first).not_to be_cached
    expect(second).to be_success
    expect(second).to be_cached
    expect(geocoder).to have_received(:request).once
    expect(weather).to have_received(:request).once
  end
end
