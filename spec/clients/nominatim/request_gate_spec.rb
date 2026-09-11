require "rails_helper"

RSpec.describe Nominatim::RequestGate do
  subject(:gate) { described_class.new }

  it "accepts the first request and another after one second" do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 11.0)

    expect(gate.call { :first }).to eq(:first)
    expect(gate.call { :next }).to eq(:next)
  end

  it "rejects early requests without executing their block" do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 10.5)
    gate.call { :first }
    executed = false

    expect { gate.call { executed = true } }.to raise_error(described_class::Busy)
    expect(executed).to be(false)
  end

  it "counts failed requests toward the limit" do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 10.5)

    expect { gate.call { raise ExternalApis::JsonClient::Unavailable } }.to raise_error(ExternalApis::JsonClient::Unavailable)
    expect { gate.call { :next } }.to raise_error(described_class::Busy)
  end

  it "admits only one of two concurrent requests" do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0)
    threads = 2.times.map do
      Thread.new do
        gate.call { :accepted }
      rescue described_class::Busy
        :rejected
      end
    end

    expect(threads.map(&:value)).to contain_exactly(:accepted, :rejected)
  end
end
