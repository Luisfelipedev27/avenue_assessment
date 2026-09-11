module Nominatim
  class Client
    REQUEST_GATE = RequestGate.new

    def initialize(http_client: ExternalApis::JsonClient.new, request_gate: REQUEST_GATE)
      @http_client = http_client
      @request_gate = request_gate
    end

    def geocode(address:)
      @request_gate.call do
        @http_client.get(ENV.fetch("NOMINATIM_URL", "https://nominatim.openstreetmap.org/search"),
          params: { q: address, format: "jsonv2", addressdetails: 1, countrycodes: "us", limit: 1 },
          headers: { "User-Agent" => "AvenueWeather/1.0", "Accept-Language" => "en" })
      end
    end
  end
end
