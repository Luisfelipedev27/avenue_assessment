module Forecasts
  class Fetch
    attr_reader :location, :forecast, :error_message

    def self.call(**args)
      new(**args).call
    end

    def initialize(address:, address_resolver: Addresses::Resolve, client: OpenMeteo::Client.new, cache: Rails.cache)
      @address = address
      @address_resolver = address_resolver
      @client = client
      @cache = cache
      @cached = false
    end

    def call
      resolve_address && load_forecast
      self
    end

    def success?
      error_message.blank?
    end

    def cached?
      @cached
    end

    private

    attr_writer :location, :forecast, :error_message

    def resolve_address
      service = @address_resolver.call(address: @address)
      if service.success?
        self.location = service.location
        true
      else
        self.error_message = service.error_message
        false
      end
    end

    def load_forecast
      @cached = true
      self.forecast = @cache.fetch(
        [ "forecasts", "v1", location.fetch(:country), location.fetch(:postal_code), "F" ],
        expires_in: 30.minutes, skip_nil: true
      ) do
        @cached = false
        fetch_forecast ? forecast : nil
      end
    end

    def fetch_forecast
      payload = @client.forecast(latitude: location.fetch(:latitude), longitude: location.fetch(:longitude))
      raise ExternalApis::JsonClient::InvalidResponse unless payload.is_a?(Hash)

      current = payload.fetch("current")
      daily = payload.fetch("daily")
      unless current.is_a?(Hash) && daily.is_a?(Hash) &&
          daily["temperature_2m_max"].is_a?(Array) && daily["temperature_2m_min"].is_a?(Array)
        raise ExternalApis::JsonClient::InvalidResponse
      end

      self.forecast = {
        temperature: current.fetch("temperature_2m"),
        high: daily["temperature_2m_max"].first,
        low: daily["temperature_2m_min"].first,
        unit: "F",
        updated_at: current.fetch("time")
      }
      validate_forecast
    rescue ExternalApis::JsonClient::Error, KeyError, TypeError
      self.forecast = nil
      self.error_message = "Unable to retrieve the forecast right now"
      false
    end

    def validate_forecast
      temperatures = forecast.values_at(:temperature, :high, :low)
      unless temperatures.all? { |value| value.is_a?(Numeric) && value.finite? } &&
          forecast[:high] >= forecast[:low] && forecast[:updated_at].is_a?(Integer) &&
          forecast[:updated_at].positive?
        raise ExternalApis::JsonClient::InvalidResponse
      end

      true
    end
  end
end
