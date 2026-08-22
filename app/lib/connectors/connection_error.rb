module Connectors
  # Anything a connector could not do. ConnectionJob records it on the
  # connection rather than letting a service-specific exception class escape.
  class ConnectionError < StandardError; end
end
