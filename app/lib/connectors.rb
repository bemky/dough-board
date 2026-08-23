# Read-only links to an outside financial institution. A connector knows how to
# talk to one service; everything above it deals in plain hashes, so adding a
# second service means adding a class here and nothing else.
module Connectors

  REGISTRY = {
    "snaptrade" => "Connectors::SnapTrade",
    "plaid" => "Connectors::Plaid"
  }.freeze

  def self.names
    REGISTRY.keys
  end

  def self.for(name)
    class_name = REGISTRY[name.to_s]
    raise ArgumentError, "Unknown connector #{name.inspect}" unless class_name
    class_name.constantize
  end

  # The connectors the app actually has credentials for. The connections page
  # offers a button per connector, and one that can only fail isn't worth
  # offering — a Dough Board set up with a Finnhub key and nothing else should
  # show no connect buttons rather than two that error.
  def self.configured
    names.select { |name| self.for(name).configured? }
  end

  # Which of the two ways of making a connection each configured connector
  # supports: reading the ones its credentials can already see, or running a
  # browser flow to make a new one. See Connectors::Base.
  def self.discoverable
    configured.select { |name| self.for(name).discoverable? }
  end

  def self.linkable
    configured.select { |name| self.for(name).linkable? }
  end

end
