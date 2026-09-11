module OpenMeteo
  class Client
    def initialize(http_client: ExternalApis::JsonClient.new)
      @http_client = http_client
    end

    def forecast(latitude:, longitude:)
      @http_client.get("https://api.open-meteo.com/v1/forecast", params: {
        latitude: latitude, longitude: longitude,
        current: "temperature_2m", daily: "temperature_2m_max,temperature_2m_min",
        temperature_unit: "fahrenheit", timeformat: "unixtime", timezone: "auto", forecast_days: 1
      })
    end
  end
end
