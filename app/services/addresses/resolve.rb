require "digest"

module Addresses
  class Resolve
    attr_reader :location, :error_message

    def self.call(**args)
      new(**args).call
    end

    def initialize(address:, client: Nominatim::Client.new, cache: Rails.cache)
      @address = address.is_a?(String) ? address.squish : ""
      @client = client
      @cache = cache
    end

    def call
      validate_address && load_location
      self
    end

    def success?
      error_message.blank?
    end

    private

    attr_writer :location, :error_message

    def validate_address
      if @address.blank?
        self.error_message = "Address is required"
        return false
      end

      unless @address.match?(/[[:alpha:]]/) && @address.match?(/\d/)
        self.error_message = "Enter a full street address, including a house number, city and state"
        return false
      end

      true
    end

    def load_location
      key = [ "addresses", "v2", "US", Digest::SHA256.hexdigest(@address.downcase) ]
      self.location = @cache.fetch(key, expires_in: 30.minutes, skip_nil: true) do
        resolve_address ? location : nil
      end
    end

    def resolve_address
      results = @client.geocode(address: @address)
      raise ExternalApis::JsonClient::InvalidResponse unless results.is_a?(Array)

      if results.empty?
        self.error_message = "Address not found"
        return false
      end

      if results.any? { |result| !result.is_a?(Hash) || !result["address"].is_a?(Hash) }
        raise ExternalApis::JsonClient::InvalidResponse
      end

      if results.map { |result| result["address"]["postcode"] }.uniq.size > 1
        self.error_message = "Multiple locations found. Include the city and state to narrow your search"
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

      unless components["house_number"].present? && components["road"].present?
        self.error_message = "A complete street address could not be confirmed. Check the house number, city and state"
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
