module Connectors
  # Anything a connector could not do. ConnectionJob records it on the
  # connection rather than letting a service-specific exception class escape.
  #
  # `code` is the provider's own error code where it has one (Plaid's
  # "ITEM_LOGIN_REQUIRED", "PRODUCTS_NOT_SUPPORTED", …), so a caller can tell
  # apart the failures that need a person from the ones that are just an empty
  # answer. It stays nil for connectors that don't report one.
  class ConnectionError < StandardError
    attr_accessor :code
  end
end
