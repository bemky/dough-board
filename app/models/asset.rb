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

  validates :type, inclusion: {in: %w(stock fund crypto cash liability balance real_estate vehicle), allow_nil: true}
  validates :symbol, uniqueness: true

  # Which valuator prices a type when the asset doesn't name one itself. A house
  # and a car aren't quoted by anybody, so they resolve away from Finnhub by
  # default; everything else keeps going there. See app/lib/valuators.
  VALUATORS_BY_TYPE = {
    "real_estate" => "manual",
    "vehicle" => "depreciation"
  }.freeze

  DEFAULT_VALUATOR = "finnhub".freeze

  # A value typed into the asset form. Recorded as a quote, which is how every
  # other price gets here too — so an override ages, sorts and renders like
  # anything else rather than being a second kind of price.
  attr_accessor :entered_value

  # Both symbol and type feed #quote_symbol — type decides whether the request
  # goes out as "BTC" or "BINANCE:BTCUSDT" — so changing either means the cached
  # quotes priced a different instrument. The valuation settings are the same
  # thing one step out: a different purchase price is a different curve. Drop
  # them; the next #current_quote refetches.
  after_update :clear_quotes, if: -> {
    saved_change_to_symbol? || saved_change_to_type? ||
      saved_change_to_valuation_source? || saved_change_to_valuation_key?
  }

  # Splits are scraped by symbol, so a new symbol invalidates them — and with
  # them every transaction's cached adjusted_quantity.
  after_update :reset_splits, if: -> { saved_change_to_symbol? && splittable? }

  after_save :record_entered_value, if: -> { entered_value.present? }


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

  # An account some institution reports only the value of: no holdings, no
  # activity, just what it's worth (Titan, cleared by Apex, is the one that
  # forced this). It's carried like cash and like a debt — dollars at a dollar
  # apiece, the count being the balance — except the asset stands in for one
  # account rather than for a kind of thing, because two managed accounts are
  # two different things being valued rather than one holding held twice.
  def balance?
    type == "balance"
  end

  # Dollars, held or owed, are worth a dollar. Nothing here is quotable.
  def face_value?
    cash? || liability? || balance?
  end

  # A house and a car are held the same way a share is — one position, some
  # number of units, a price each — so nothing downstream has to know what they
  # are. What differs is only where the price comes from, and that's the
  # valuator's business rather than a branch here.
  #
  # Only a security splits, though: a house has no split history to scrape, and
  # splithistory.com would happily be asked for "PROPERTY:12-OAK-ST".
  def splittable?
    !face_value? && !VALUATORS_BY_TYPE.key?(type.to_s)
  end

  def valuator_name
    valuation_source.presence || VALUATORS_BY_TYPE[type.to_s] || DEFAULT_VALUATOR
  end

  def valuator
    Valuators.for(valuator_name)
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

  # A quote already on hand and still current, or nil — never hits the network.
  # Pages that render many assets at once (the portfolio index) use this instead
  # of `current_quote`/`price` so rendering never blocks; the page's JS fills in
  # fresh prices afterward via AssetsController#quote.
  #
  # How long "current" is belongs to the valuator: Finnhub's 24 hours is a cache
  # of something that moves by the minute, while a scraped house price never
  # expires — letting it would blank the holding out rather than improve it.
  def cached_quote
    ttl = valuator.quote_ttl
    scope = ttl ? quotes.where(quoted_at: ttl.ago..) : quotes
    scope.order(quoted_at: :desc).first
  end

  # Whether the periodic refresh should ask this asset's source again. Distinct
  # from #cached_quote's window: a stock is re-quoted every half hour but its
  # last quote stays usable for a day, and a house is the other way round.
  def quote_due?
    interval = valuator.refresh_interval
    return false if interval.nil?

    latest = quotes.order(quoted_at: :desc).first
    latest.nil? || latest.quoted_at <= interval.ago
  end

  def cached_price
    return 1.0 if face_value?
    cached_quote&.price
  end
  
  def load_splits(force=false)
    return splits unless splittable?
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
    # Reset first: a quote made through `Quote.create(asset: self)` is not
    # appended to an already-loaded association, so destroy_all would leave
    # exactly the quote most likely to be the stale one behind.
    quotes.reset
    quotes.destroy_all
  end

  # after_update runs before after_save, so a save that both changes the source
  # and enters a value clears the old quotes first and keeps this one.
  private def record_entered_value
    Quote.create(asset: self, price: entered_value.to_f, quoted_at: Time.current)
    self.entered_value = nil
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