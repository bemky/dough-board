module Valuators
  # The original source, now one of several. Every existing asset resolves here
  # because Asset::VALUATORS_BY_TYPE only names the new types.
  class Finnhub < Base
    # `::Finnhub` deliberately: inside Valuators::Finnhub a bare `Finnhub`
    # resolves to this class, not the singleton in config/initializers.
    def price(asset)
      ::Finnhub.quote(asset.quote_symbol)
    end

    def configured?
      Rails.application.credentials.finnhub&.try(:api_key).present?
    end
  end
end
