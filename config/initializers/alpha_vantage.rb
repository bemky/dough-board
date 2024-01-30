require 'uri'
require 'net/http'

class AlphaVantage
  include Singleton

  def initialize
    @api_key = Rails.application.credentials.alpha_vantage&.try(:api_key)
  end
  
  def quote(symbol)
    url = URI("https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=#{symbol}&apikey=#{@api_key}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    response = http.request(Net::HTTP::Get.new(url))
    JSON.parse(response.read_body)["Global Quote"].transform_keys {|key|
      key.sub(/\d+\.\s/, "")
    }
  end

  # Delegates all uncauge class method calls to the singleton
  def self.method_missing(method, *args, &block)
    instance.__send__(method, *args, &block)
  end
end
