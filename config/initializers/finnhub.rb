require 'finnhub_ruby'

FinnhubRuby.configure do |config|
  config.api_key['api_key'] = Rails.application.credentials.finnhub&.try(:api_key)
end

class Finnhub
  include Singleton

  def initialize
    @client = FinnhubRuby::DefaultApi.new
  end

  # Returns the current price (the "c" field) for +symbol+, or nil if Finnhub
  # returns no data (e.g. an unknown symbol yields c=0) or the request fails
  # (e.g. a rate-limited request raises FinnhubAPIException).
  def quote(symbol)
    price = @client.quote(symbol)["c"]
    price if price && price != 0
  rescue FinnhubRuby::FinnhubAPIException, FinnhubRuby::FinnhubRequestException
    nil
  end

  # Delegates all uncaught class method calls to the singleton
  def self.method_missing(method, *args, &block)
    instance.__send__(method, *args, &block)
  end
end
