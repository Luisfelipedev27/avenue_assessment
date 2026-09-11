require "rails_helper"

RSpec.describe "Forecast search", type: :request do
  let(:address) { "350 5th Avenue, New York, NY" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    stub_const("Nominatim::Client::REQUEST_GATE", Nominatim::RequestGate.new)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def stub_providers
    geocoder = stub_http_response("nominatim.openstreetmap.org", body: JSON.generate(api_fixture("nominatim")))
    weather = stub_http_response("api.open-meteo.com", body: JSON.generate(api_fixture("open_meteo")))
    [ geocoder, weather ]
  end

  it "shows an accessible form without calling the providers" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css('form[action="/forecast"][method="post"]')).to be_present
    expect(page.at_css('label[for="address"]').text).to eq("US address")
    expect(page.at_css('#address[required]')).to be_present
    expect(page.at_css("#forecast-heading").text).to eq("Your forecast will appear here")
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "displays the forecast, location, units, timestamp and attribution" do
    stub_providers
    post forecast_path, params: { address: address }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(page.at_css("#current-temperature").text.gsub(/\s+/, "")).to eq("72.5°F")
    expect(page.at_css("#high-temperature").text.strip).to eq("78.8 °F")
    expect(page.at_css("#low-temperature").text.strip).to eq("64.4 °F")
    expect(page.at_css("#forecast-location").text).to include("Empire State Building")
    expect(page.text).to include("ZIP 10118")
    expect(page.at_css("#cache-status").text.strip).to eq("Fresh forecast")
    expect(page.at_css("time")["datetime"]).to eq(Time.at(1789063200).utc.iso8601)
    expect(page.at_css('a[href="https://open-meteo.com/"]')).to be_present
    expect(page.at_css('a[href="https://www.openstreetmap.org/copyright"]')).to be_present
    expect(page.at_css("#address")["value"]).to eq(address)
  end

  it "shows the cache indicator on the next request without calling either API again" do
    geocoder, weather = stub_providers
    post forecast_path, params: { address: address }
    post forecast_path, params: { address: address }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#cache-status").text.strip).to eq("From cache")
    expect(geocoder).to have_received(:request).once
    expect(weather).to have_received(:request).once
  end

  it "does not confuse a cached address with a cached forecast" do
    geocoder, weather = stub_providers
    Addresses::Resolve.call(address: address)
    post forecast_path, params: { address: address }

    expect(page.at_css("#cache-status").text.strip).to eq("Fresh forecast")
    expect(geocoder).to have_received(:request).once
    expect(weather).to have_received(:request).once
  end

  [ nil, " ", { unexpected: "value" }, [ "New York" ] ].each do |input|
    it "rejects invalid address input: #{input.inspect}" do
      post forecast_path, params: { address: input }

      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css('[role="alert"]').text).to eq("Address is required")
      expect(page.at_css("#cache-status")).to be_nil
      expect(Net::HTTP).not_to have_received(:start)
    end
  end

  it "rejects a house number alone before calling a provider" do
    post forecast_path, params: { address: "350" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css('[role="alert"]').text).to include("Enter a full street address")
    expect(page.at_css("#address")["value"]).to eq("350")
    expect(page.at_css("#current-temperature")).to be_nil
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "preserves and escapes the address when the location cannot be found" do
    stub_http_response("nominatim.openstreetmap.org", body: "[]")
    input = '350 Fifth Avenue <script>alert("test")</script>'
    post forecast_path, params: { address: input }

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css("#address")["value"]).to eq(input)
    expect(page.at_css('[role="alert"]').text).to eq("Address not found")
    expect(response.body).not_to include(input)
  end

  it "shows a useful message when the provider is unavailable" do
    stub_http_response("nominatim.openstreetmap.org", status: "503", body: "unavailable")
    post forecast_path, params: { address: address }

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css('[role="alert"]').text).to eq("Unable to resolve the address right now")
  end

  it "shows a retry message when searches are too frequent" do
    allow(Nominatim::Client::REQUEST_GATE).to receive(:call).and_raise(Nominatim::RequestGate::Busy)
    post forecast_path, params: { address: address }

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css('[role="alert"]').text).to eq("Please wait a moment before searching again")
  end

  it "does not show a forecast when the weather service fails" do
    stub_http_response("nominatim.openstreetmap.org", body: JSON.generate(api_fixture("nominatim")))
    stub_http_response("api.open-meteo.com", status: "500", body: "unavailable")
    post forecast_path, params: { address: address }

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css('[role="alert"]').text).to eq("Unable to retrieve the forecast right now")
    expect(page.at_css("#current-temperature")).to be_nil
  end
end
