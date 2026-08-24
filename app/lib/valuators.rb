# Where an asset's price comes from. Finnhub prices a security; a car is worth
# what a depreciation curve says; a house is worth whatever you last decided it
# was; a dollar is worth a dollar. A valuator knows one of those answers;
# everything above it gets a Float or nil, so adding a source means adding a
# class here and nothing else.
module Valuators

  REGISTRY = {
    "finnhub" => "Valuators::Finnhub",
    "depreciation" => "Valuators::Depreciation",
    "manual" => "Valuators::Manual"
  }.freeze

  def self.names
    REGISTRY.keys
  end

  def self.for(name)
    class_name = REGISTRY[name.to_s]
    raise ArgumentError, "Unknown valuator #{name.inspect}" unless class_name
    class_name.constantize
  end

  # What the asset form offers: [[label, name], ...]. A valuator with no
  # credentials behind it can only fail, so it isn't worth offering — the same
  # reasoning as Connectors.configured.
  def self.selectable
    names.select { |name| self.for(name).configured? }
         .map { |name| [self.for(name).label, name] }
  end

  # Every key any valuator declares, which is what the controller permits into
  # assets.valuation_key. Permitting the column wholesale would let a form post
  # write arbitrary JSON onto an asset.
  def self.key_names
    names.flat_map { |name| self.for(name).keys.map { |key| key[:name].to_s } }.uniq
  end

end
