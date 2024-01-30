require 'uri'
require 'net/http'

class AlphaVantage
  include Singleton

  def initialize
    @api_key = Rails.application.credentials.alpha_vantage&.try(:api_key)
  end
  
  def quote(symbol)
    data = get(function: 'GLOBAL_QUOTE', symbol: symbol)
    
    data["Global Quote"].transform_keys {|key|
      key.sub(/\d+\.\s/, "")
    }
  end
  
  def time_series(symbol, options={})
    data = get(options.merge(
      function: 'TIME_SERIES_DAILY',
      symbol: symbol
    ))
    
    data = data["Time Series (Daily)"]
    data.each do |k, v|
      data[k] = v.transform_keys {|key|
        key.sub(/\d+\.\s/, "")
      }
    end
  end
  
  def get(params)
    params.merge!(apikey: @api_key)
    url = URI("https://www.alphavantage.co/query?#{URI.encode_www_form(params)}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    response = http.request(Net::HTTP::Get.new(url))
    JSON.parse(response.read_body)
  end

  # Delegates all uncauge class method calls to the singleton
  def self.method_missing(method, *args, &block)
    instance.__send__(method, *args, &block)
  end
end
