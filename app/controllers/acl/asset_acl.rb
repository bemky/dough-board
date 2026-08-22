module AssetACL

  # symbol/type/exchange drive quoting and split scraping (see Asset#quote_symbol),
  # so they're the fields worth correcting by hand. splits_updated_at is a cache
  # timestamp and stays out of the form.
  def attributes
    [
      :symbol,
      :name,
      :type,
      :exchange
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
    {}
  end

end
