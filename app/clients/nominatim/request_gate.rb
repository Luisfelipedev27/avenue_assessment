module Nominatim
  class RequestGate
    class Busy < ExternalApis::JsonClient::Error; end

    # The public API allows one request per second across the application.
    # This in-memory gate requires a single application process/instance.
    # https://operations.osmfoundation.org/policies/nominatim/
    def initialize
      @mutex = Mutex.new
      @last_request_at = nil
    end

    def call
      @mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Busy if @last_request_at && now - @last_request_at < 1

        @last_request_at = now
      end

      yield
    end
  end
end
