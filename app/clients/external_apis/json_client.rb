require "net/http"
require "json"

module ExternalApis
  class JsonClient
    class Error < StandardError; end
    class InvalidResponse < Error; end
    class Unavailable < Error; end

    class HttpError < Error; end

    def get(url, params:, headers: {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 5, read_timeout: 5, write_timeout: 5) do |http|
        http.max_retries = 0
        http.request(Net::HTTP::Get.new(uri, { "Accept" => "application/json" }.merge(headers)))
      end

      raise HttpError, "External service returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      raise InvalidResponse unless payload.is_a?(Hash) || payload.is_a?(Array)

      payload
    rescue JSON::ParserError, Net::HTTPBadResponse
      raise InvalidResponse, "External service returned an invalid response"
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
      raise Unavailable, "External service is unavailable"
    end
  end
end
