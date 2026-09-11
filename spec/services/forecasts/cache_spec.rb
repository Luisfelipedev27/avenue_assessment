require "rails_helper"

RSpec.describe Forecasts::Fetch do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:client) { instance_double(OpenMeteo::Client, forecast: api_fixture("open_meteo")) }
  let(:location) { { address: "First address", postal_code: "10118", country: "US", latitude: 40.7484421, longitude: -73.9856589 } }
  let(:resolved) { instance_double(Addresses::Resolve, success?: true, location: location) }
  let(:resolver) { class_double(Addresses::Resolve, call: resolved) }

  def fetch(address = "First address")
    described_class.call(address: address, address_resolver: resolver, client: client, cache: cache)
  end

  it "marks the first result as fresh and subsequent results as cached" do
    first = fetch
    second = fetch

    expect(first).to be_success
    expect(first).not_to be_cached
    expect(second).to be_success
    expect(second).to be_cached
    expect(second.forecast).to eq(first.forecast)
    expect(client).to have_received(:forecast).once
  end

  it "shares forecasts between different addresses in the same ZIP while preserving the requested location" do
    first = fetch
    second_location = location.merge(address: "Second address", latitude: 40.7485)
    allow(resolved).to receive(:location).and_return(second_location)
    second = fetch("Second address")

    expect(second).to be_cached
    expect(second.forecast).to eq(first.forecast)
    expect(second.location).to eq(second_location)
    expect(client).to have_received(:forecast).once
  end

  it "isolates different ZIP codes" do
    fetch
    allow(resolved).to receive(:location).and_return(location.merge(postal_code: "02108"))

    expect(fetch).not_to be_cached
    expect(client).to have_received(:forecast).twice
  end

  it "includes the country in the cache key" do
    fetch
    allow(resolved).to receive(:location).and_return(location.merge(country: "OTHER"))

    expect(fetch).not_to be_cached
    expect(client).to have_received(:forecast).twice
  end

  it "expires after 30 minutes without extending the lifetime on cache reads" do
    travel_to(Time.zone.local(2026, 9, 11, 12)) do
      first = fetch
      travel 29.minutes
      expect(fetch).to be_cached
      travel 1.minute + 1.second
      payload = api_fixture("open_meteo")
      payload["current"]["temperature_2m"] = 80
      allow(client).to receive(:forecast).and_return(payload)

      refreshed = fetch
      expect(refreshed).not_to be_cached
      expect(refreshed.forecast[:temperature]).to eq(80)
      expect(first.forecast[:temperature]).to eq(72.5)
      expect(client).to have_received(:forecast).twice
    end
  end

  it "serves a cached forecast even if the weather provider becomes unavailable" do
    fetch
    allow(client).to receive(:forecast).and_raise(ExternalApis::JsonClient::Unavailable)

    expect(fetch).to be_success
    expect(fetch).to be_cached
    expect(client).to have_received(:forecast).once
  end

  it "does not cache provider failures" do
    allow(client).to receive(:forecast).and_raise(ExternalApis::JsonClient::Unavailable)
    failed = fetch
    expect(failed).not_to be_success
    expect(failed).not_to be_cached

    allow(client).to receive(:forecast).and_return(api_fixture("open_meteo"))
    recovered = fetch
    expect(recovered).to be_success
    expect(recovered).not_to be_cached
    expect(client).to have_received(:forecast).twice
  end

  it "does not cache invalid forecast data" do
    allow(client).to receive(:forecast).and_return({})
    expect(fetch).not_to be_success
    allow(client).to receive(:forecast).and_return(api_fixture("open_meteo"))

    expect(fetch).to be_success
    expect(client).to have_received(:forecast).twice
  end

  it "does not report a cache hit when address resolution fails" do
    allow(resolved).to receive_messages(success?: false, error_message: "Address not found")

    result = fetch
    expect(result).not_to be_success
    expect(result).not_to be_cached
    expect(client).not_to have_received(:forecast)
  end
end
