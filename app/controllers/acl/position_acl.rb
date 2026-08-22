module PositionACL

  # `value` and `cost_basis` are derived on save, so they're readable but never
  # written directly. Whether a position may be edited at all is a property of
  # its account (Account#manual_positions?), not of the row.
  def attributes
    [
      :account_id,
      :symbol,
      :asset_id,
      :as_of,
      :units,
      :price,
      :average_price,
      :currency
    ]
  end

  def nested
    [
    ]
  end

  # Permitted sort keys for the positions table headers. Relation keys are
  # requested as `order[asset.symbol]=asc`.
  def orders
    [
      :as_of,
      :units,
      :price,
      :value,
      :cost_basis,
      {asset: [:name, :symbol]},
      {account: [:name, :institution_name]}
    ]
  end

  def includes
    {asset: true, account: true}
  end

end
