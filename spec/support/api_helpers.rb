require "net/http"

module ApiHelpers
  def api_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/files/#{name}.json").read)
  end

  def stub_http_response(host, body:, status: "200")
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(status).new("1.1", status, "Response")
    allow(response).to receive(:body).and_return(body)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:max_retries=).with(0)
    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with(
      host, 443, use_ssl: true, open_timeout: 5, read_timeout: 5, write_timeout: 5
    ).and_yield(http)
    http
  end
end

RSpec.configure do |config|
  config.include ApiHelpers

  config.before do
    allow(Net::HTTP).to receive(:start).and_raise("Unexpected HTTP request: stub the provider in this spec")
  end
end
