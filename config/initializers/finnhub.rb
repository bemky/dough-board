require 'finnhub_ruby'

FinnhubRuby.configure do |config|
  config.api_key['api_key'] = Rails.application.credentials.finnhub&.try(:api_key)
end

class Finnhub
  include Singleton

  # Finnhub's free tier allows 60 calls/minute; 1.1s spacing keeps every
  # caller (including many concurrent quote-refresh requests from the
  # portfolio page's JS) safely under that regardless of how many pile up.
  MIN_CALL_INTERVAL = 1.1

  def initialize
    @client = FinnhubRuby::DefaultApi.new
    @mutex = Mutex.new
    @last_called_at = nil
  end

  # Returns the current price (the "c" field) for +symbol+, or nil if Finnhub
  # returns no data (e.g. an unknown symbol yields c=0) or the request fails
  # (e.g. a rate-limited request raises FinnhubAPIException).
  def quote(symbol)
    throttle
    price = @client.quote(symbol)["c"]
    price if price && price != 0
  rescue FinnhubRuby::FinnhubAPIException, FinnhubRuby::FinnhubRequestException
    nil
  end

  # Delegates all uncaught class method calls to the singleton
  def self.method_missing(method, *args, &block)
    instance.__send__(method, *args, &block)
  end

  private

  # Serializes calls across every thread/request so bursts (e.g. a page
  # firing one quote request per holding) get spaced out instead of hitting
  # Finnhub's rate limit at once.
  def throttle
    @mutex.synchronize do
      if @last_called_at
        wait = MIN_CALL_INTERVAL - (Time.now - @last_called_at)
        sleep(wait) if wait > 0
      end
      @last_called_at = Time.now
    end
  end
end
