module TransactionACL

  def attributes
    [
      :executed_at,
      :symbol,
      :account_id,
      :quantity,
      :value,
      :type,
      :foreign_id
    ]
  end

  def nested
    [
    ]
  end

  # Permitted sort keys for the transactions table headers. Relation keys are
  # requested as `order[asset.symbol]=asc`, which StandardAPI::Orders expands
  # into `{asset: {symbol: 'asc'}}` for activerecord-sort.
  def orders
    [
      :executed_at,
      :type,
      :quantity,
      :adjusted_quantity,
      :value,
      {asset: [:name, :symbol]},
      {account: [:name, :provider]}
    ]
  end

  def includes
    {}
  end

end