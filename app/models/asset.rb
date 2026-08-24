class Asset < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :exchange, optional: true

  has_many :transactions
  has_many :positions, dependent: :delete_all
  has_many :quotes, -> { order(quoted_at: :desc)}, dependent: :destroy
  has_many :splits

  normalizes :symbol, with: -> symbol { symbol.upcase }

  # The type select validates with allow_nil, but a form's blank option submits
  # "", which is neither nil nor a listed value — without this, saving an asset
  # whose type was never touched fails validation on it.
  normalizes :type, with: -> value { value.presence }

  validates :type, inclusion: {in: %w(stock fund crypto cash liability), allow_nil: true}

  # The kinds of debt, and what each one is called the first time it's created.
  # A debt asset is the *kind* rather than the account, so every card across
  # every institution folds into one holding — which means this vocabulary has
  # to be shared: a mortgage kept by hand and one synced from Plaid are the same
  # holding or they are two, and two would be wrong.
  DEBT_NAMES = {
    "DEBT:CREDIT_CARD" => "Credit Card Debt",
    "DEBT:LINE_OF_CREDIT" => "Line of Credit",
    "DEBT:AUTO_LOAN" => "Auto Loan",
    "DEBT:HOME_LOAN" => "Home Loan",
    "DEBT:STUDENT_LOAN" => "Student Loan",
    "DEBT:LOAN" => "Loan"
  }.freeze
  validates :symbol, uniqueness: true

  # Both symbol and type feed #quote_symbol — type decides whether the request
  # goes out as "BTC" or "BINANCE:BTCUSDT" — so changing either means the cached
  # quotes priced a different instrument. Drop them; the next #current_quote
  # refetches.
  after_update :clear_quotes, if: -> { saved_change_to_symbol? || saved_change_to_type? }

  # Splits are scraped by symbol, so a new symbol invalidates them — and with
  # them every transaction's cached adjusted_quantity.
  after_update :reset_splits, if: -> { saved_change_to_symbol? }


  # A cash balance is carried as a position against a cash asset so it shows up
  # in the treemap and account totals like anything else. It is worth its face
  # value; there is nothing to quote.
  def cash?
    type == "cash"
  end

  # A debt — a card balance, a mortgage — is carried the same way cash is: a
  # position of dollars worth face value, negative because they're owed rather
  # than held. The asset is the *kind* of debt, so every card across every
  # institution folds into one holding in the portfolio.
  def liability?
    type == "liability"
  end

  # Dollars, held or owed, are worth a dollar. Nothing here is quotable.
  def face_value?
    cash? || liability?
  end

  def price
    return 1.0 if face_value?
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
    return 1.0 if face_value?
    cached_quote&.price
  end
  
  def load_splits(force=false)
    return splits if !force && splits_updated_at && splits_updated_at > 24.hours.ago
    splits = SplitHistoryScraper.splits(symbol).map do |data|
      self.splits.find{|split| split.split_at == data[0]} || Split.create(asset: self, split_at: data[0], ratio: data[1])
    end
    touch(:splits_updated_at)
    # Split.create above doesn't append to an already-loaded association, so
    # callers reading `asset.splits` afterward (LoadSplitsJob) would otherwise
    # still see the pre-scrape set.
    self.splits.reset
    splits
  end

  private def clear_quotes
    quotes.destroy_all
  end

  # Dropping the splits alone isn't enough: adjusted_quantity is computed once
  # at save time and set_adjusted_quantity won't redo the work unless forced,
  # so transactions would keep applying the old symbol's ratios indefinitely.
  # LoadSplitsJob rescrapes and recomputes them off-request.
  private def reset_splits
    splits.destroy_all
    update_column(:splits_updated_at, nil)
    LoadSplitsJob.perform_later(self)
  end
end