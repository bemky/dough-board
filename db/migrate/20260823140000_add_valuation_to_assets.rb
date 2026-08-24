class AddValuationToAssets < ActiveRecord::Migration[8.1]
  def change
    # Which valuator prices this asset. Null means "whatever its type implies"
    # (see Asset::VALUATORS_BY_TYPE), so every existing row keeps going to
    # Finnhub without being rewritten.
    add_column :assets, :valuation_source, :string

    # Whatever that valuator needs to do its job — a Zillow listing URL, a car's
    # purchase price and date. The shape is the valuator's business; nothing
    # above it reads a key by name.
    add_column :assets, :valuation_key, :json
  end
end
