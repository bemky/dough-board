class Asset < ApplicationRecord
  self.inheritance_column = nil

  has_many :transactions
  has_many :quotes, -> { order(quoted_at: :desc)}, dependent: :destroy
  has_many :splits
  
  normalizes :symbol, with: -> symbol { symbol.upcase }

  validates :type, inclusion: {in: %w(stock fund crypto), allow_nil: true}
  validates :exchange, inclusion: {in: %w(nyse nasdaq), allow_nil: true}
  
  def price
    current_quote&.price
  end

  # The symbol to request a Finnhub quote for. Crypto needs an exchange-prefixed
  # trading pair (e.g. "BTC" -> "BINANCE:BTCUSDT"); stocks/funds use the symbol as-is.
  def quote_symbol
    type == "crypto" ? "BINANCE:#{symbol}USDT" : symbol
  end

  def current_quote
    cached_quote || Quote.create(asset: self)
  end

  # A <24h-old quote already on hand, or nil — never hits Finnhub. Pages that
  # render many assets at once (the portfolio index) use this instead of
  # `current_quote`/`price` so rendering never blocks on the Finnhub API; the
  # page's JS fills in fresh prices afterward via AssetsController#quote.
  def cached_quote
    quotes.filter(quoted_at: {gt: 24.hours.ago}).order(quoted_at: :desc).first
  end

  def cached_price
    cached_quote&.price
  end
  
  def load_splits(force=false)
    return splits if !force && splits_updated_at && splits_updated_at > 24.hours.ago
    splits = SplitHistoryScraper.splits(symbol).map do |data|
      self.splits.find{|split| split.split_at == data[0]} || Split.create(asset: self, split_at: data[0], ratio: data[1])
    end
    touch(:splits_updated_at)
    splits
  end
end