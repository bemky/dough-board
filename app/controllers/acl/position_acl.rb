module PositionACL

  # A position entered here is somebody's deliberate entry, so `source` is not
  # writable — Position defaults it to "manual" and only DerivePositionsJob
  # marks a row "derived". Letting the form set it would hand a row to the job
  # to overwrite. `value` and `cost_basis` are derived on save.
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
      :source,
      {asset: [:name, :symbol]},
      {account: [:name, :institution_name]}
    ]
  end

  def includes
    {asset: true, account: true}
  end

end
