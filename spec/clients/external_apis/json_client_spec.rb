require "rails_helper"

RSpec.describe ExternalApis::JsonClient do
  subject(:client) { described_class.new }

  let(:url) { "https://example.com/search" }

  it "encodes query parameters and requests JSON over HTTPS with bounded timeouts" do
    http = stub_http_response("example.com", body: '{"results":[]}')

    expect(client.get(url, params: { q: "350 5th Ave & Broadway", key: "secret" })).to eq("results" => [])
    expect(http).to have_received(:max_retries=).with(0)
    expect(http).to have_received(:request) do |request|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request["Accept"]).to eq("application/json")
      expect(URI.decode_www_form(request.uri.query).to_h).to eq(
        "q" => "350 5th Ave & Broadway", "key" => "secret"
      )
    end
  end

  [ "401", "429", "500", "302" ].each do |status|
    it "rejects HTTP #{status} without exposing the response or credentials" do
      stub_http_response("example.com", status: status, body: "secret provider detail")

      expect { client.get(url, params: { key: "secret" }) }
        .to raise_error(described_class::HttpError) { |error|
          expect(error.message).to eq("External service returned HTTP #{status}")
          expect(error.message).not_to include("secret")
        }
    end
  end

  [ "not json", "null", "42" ].each do |body|
    it "rejects an invalid JSON object: #{body}" do
      stub_http_response("example.com", body: body)

      expect { client.get(url, params: {}) }.to raise_error(described_class::InvalidResponse)
    end
  end

  it "converts a malformed HTTP response into a client error" do
    http = stub_http_response("example.com", body: "")
    allow(http).to receive(:request).and_raise(Net::HTTPBadResponse, "invalid status line")

    expect { client.get(url, params: {}) }.to raise_error(described_class::InvalidResponse)
  end

  [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError ].each do |error|
    it "handles #{error}" do
      allow(Net::HTTP).to receive(:start).and_raise(error)

      expect { client.get(url, params: {}) }.to raise_error(described_class::Unavailable)
    end
  end
end
