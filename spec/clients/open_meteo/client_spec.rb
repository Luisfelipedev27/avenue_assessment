require "rails_helper"

RSpec.describe OpenMeteo::Client do
  it "requests current temperature and today's high and low by coordinates without credentials" do
    http = stub_http_response("api.open-meteo.com", body: JSON.generate(api_fixture("open_meteo")))
    payload = described_class.new.forecast(latitude: 40.7484421, longitude: -73.9856589)

    expect(payload.fetch("current").fetch("temperature_2m")).to eq(72.5)
    expect(http).to have_received(:request) do |request|
      expect(request.uri.path).to eq("/v1/forecast")
      expect(URI.decode_www_form(request.uri.query).to_h).to eq(
        "latitude" => "40.7484421", "longitude" => "-73.9856589",
        "current" => "temperature_2m", "daily" => "temperature_2m_max,temperature_2m_min",
        "temperature_unit" => "fahrenheit", "timeformat" => "unixtime",
        "timezone" => "auto", "forecast_days" => "1"
      )
    end
  end
end
