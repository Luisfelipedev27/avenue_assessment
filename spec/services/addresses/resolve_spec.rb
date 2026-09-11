require "rails_helper"

RSpec.describe Addresses::Resolve do
  let(:client) { instance_double(Nominatim::Client, geocode: payload) }
  let(:payload) { api_fixture("nominatim") }

  def resolve(address = "350 5th Ave, New York")
    described_class.call(address: address, client: client)
  end

  it "normalizes the input and returns a postal location" do
    service = resolve(" 350  5th Ave, New York \n")

    expect(service).to be_success
    expect(service.location).to eq(
      address: payload.first["display_name"], postal_code: "10118",
      country: "US", latitude: 40.7484421, longitude: -73.9856589
    )
    expect(client).to have_received(:geocode).with(address: "350 5th Ave, New York")
  end

  [ nil, "", " \n ", [], {} ].each do |address|
    it "rejects missing or invalid input: #{address.inspect}" do
      service = resolve(address)

      expect(service).not_to be_success
      expect(service.error_message).to eq("Address is required")
      expect(client).not_to have_received(:geocode)
    end
  end

  [ "350", "10118", "...", "New York" ].each do |input|
    it "rejects incomplete input #{input.inspect} without a lookup" do
      service = resolve(input)

      expect(service).not_to be_success
      expect(service.error_message).to include("Enter a full street address")
      expect(client).not_to have_received(:geocode)
    end
  end

  it "rejects a street-only match instead of treating it as a confirmed address" do
    payload.first["address"].delete("house_number")

    service = resolve
    expect(service).not_to be_success
    expect(service.location).to be_nil
    expect(service.error_message).to include("complete street address could not be confirmed")
  end

  it "asks for clarification when matches belong to different ZIP codes" do
    other = Marshal.load(Marshal.dump(payload.first))
    other["address"]["postcode"] = "10001"
    payload << other

    expect(resolve.error_message).to include("Multiple locations found")
  end

  it "accepts duplicate matches within the same ZIP code" do
    payload << payload.first.dup

    expect(resolve).to be_success
  end

  it "reports an address that could not be found" do
    payload.clear

    expect(resolve.error_message).to eq("Address not found")
  end

  it "normalizes ZIP+4 and preserves leading zeros" do
    payload.first["address"]["postcode"] = " 02108-1234 "

    expect(resolve.location[:postal_code]).to eq("02108")
  end

  [ nil, "", "1000", "ABCDE" ].each do |postal_code|
    it "rejects an invalid ZIP code: #{postal_code.inspect}" do
      payload.first["address"]["postcode"] = postal_code

      service = resolve
      expect(service).not_to be_success
      expect(service.location).to be_nil
      expect(service.error_message).to include("valid ZIP code")
    end
  end

  it "rejects locations outside the US" do
    payload.first["address"]["country_code"] = "ca"

    expect(resolve.error_message).to eq("Only US addresses are supported")
  end

  [ nil, {}, [ nil ], [ {} ] ].each do |results|
    it "handles malformed results: #{results.inspect}" do
      allow(client).to receive(:geocode).and_return(results)

      expect(resolve.error_message).to eq("Unable to resolve the address right now")
    end
  end

  it "rejects invalid coordinates" do
    payload.first["lat"] = "100"

    expect(resolve).not_to be_success
  end

  it "reports requests that arrive too quickly" do
    allow(client).to receive(:geocode).and_raise(Nominatim::RequestGate::Busy)

    expect(resolve.error_message).to eq("Please wait a moment before searching again")
  end

  [ ExternalApis::JsonClient::Unavailable, ExternalApis::JsonClient::InvalidResponse ].each do |error|
    it "handles #{error}" do
      allow(client).to receive(:geocode).and_raise(error)

      expect(resolve.error_message).to eq("Unable to resolve the address right now")
    end
  end
end
