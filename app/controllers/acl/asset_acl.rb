module AssetACL

  # symbol/type/exchange drive quoting and split scraping (see Asset#quote_symbol),
  # so they're the fields worth correcting by hand. splits_updated_at is a cache
  # timestamp and stays out of the form.
  #
  # valuation_key is permitted key by key rather than wholesale: it's a json
  # column, and permitting the column would let a form post write arbitrary
  # JSON onto an asset. Valuators.key_names is the union of what the valuators
  # declare they need.
  def attributes
    [
      :symbol,
      :name,
      :type,
      :exchange_id,
      :valuation_source,
      :entered_value,
      {valuation_key: Valuators.key_names}
    ]
  end

  def nested
    [
    ]
  end

  def orders
    [
    ]
  end

  def includes
    {exchange: true}
  end

end
