# Read-only links to an outside financial institution. A connector knows how to
# talk to one service; everything above it deals in plain hashes, so adding a
# second service means adding a class here and nothing else.
module Connectors

  REGISTRY = {
    "snaptrade" => "Connectors::SnapTrade"
  }.freeze

  def self.names
    REGISTRY.keys
  end

  def self.for(name)
    class_name = REGISTRY[name.to_s]
    raise ArgumentError, "Unknown connector #{name.inspect}" unless class_name
    class_name.constantize
  end

end
