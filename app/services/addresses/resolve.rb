module Addresses
  class Resolve
    attr_reader :location, :error_message

    def self.call(**args)
      new(**args).call
    end

    def initialize(address:, client: Nominatim::Client.new)
      @address = address.is_a?(String) ? address.squish : ""
      @client = client
    end

    def call
      validate_address && resolve_address
      self
    end

    def success?
      error_message.blank?
    end

    private

    attr_writer :location, :error_message

    def validate_address
      return true if @address.present?

      self.error_message = "Address is required"
      false
    end

    def resolve_address
      results = @client.geocode(address: @address)
      raise ExternalApis::JsonClient::InvalidResponse unless results.is_a?(Array)

      if results.empty?
        self.error_message = "Address not found"
        return false
      end

      build_location(results.first)
    rescue Nominatim::RequestGate::Busy
      self.error_message = "Please wait a moment before searching again"
      false
    rescue ExternalApis::JsonClient::Error, KeyError, TypeError, ArgumentError
      self.error_message = "Unable to resolve the address right now"
      false
    end

    def build_location(result)
      raise ExternalApis::JsonClient::InvalidResponse unless result.is_a?(Hash)

      components = result.fetch("address")
      raise ExternalApis::JsonClient::InvalidResponse unless components.is_a?(Hash)

      unless components["country_code"] == "us"
        self.error_message = "Only US addresses are supported"
        return false
      end

      postal_code = components["postcode"].to_s.strip
      unless postal_code.match?(/\A\d{5}(?:-\d{4})?\z/)
        self.error_message = "A valid ZIP code could not be found for this address"
        return false
      end

      latitude = Float(result.fetch("lat"))
      longitude = Float(result.fetch("lon"))
      unless latitude.between?(-90, 90) && longitude.between?(-180, 180) &&
          result["display_name"].is_a?(String) && result["display_name"].present?
        raise ExternalApis::JsonClient::InvalidResponse
      end

      self.location = {
        address: result["display_name"], postal_code: postal_code.first(5),
        country: "US", latitude: latitude, longitude: longitude
      }
      true
    end
  end
end
