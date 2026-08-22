module Connectors
  # What every connector has to answer, in Dough Board's own vocabulary. The
  # shapes below are what ConnectionJob consumes; nothing service-specific —
  # no SDK objects, no provider field names — escapes a subclass.
  #
  # Follows the Singleton + class-delegation pattern used by Finnhub and
  # SplitHistoryScraper (config/initializers), so callers write
  # `Connectors::SnapTrade.accounts(connection)`.
  class Base
    include Singleton

    # **kwargs is load-bearing: without it Ruby 3 collects a call's keywords
    # into a positional Hash, and `transactions(connection, account, since:)`
    # arrives at the instance as three positional arguments.
    def self.method_missing(method, *args, **kwargs, &block)
      instance.__send__(method, *args, **kwargs, &block)
    end

    def self.respond_to_missing?(method, include_private = false)
      instance.respond_to?(method, include_private) || super
    end

    # [{foreign_id:, name:, number:, institution_name:}]
    def accounts(connection)
      raise NotImplementedError
    end

    # The account's uninvested cash, or nil if the service doesn't report it.
    def cash(connection, account)
      nil
    end

    # [{symbol:, name:, type:, exchange_mic:, figi_code:, units:, price:,
    #   average_price:, currency:}]
    def positions(connection, account)
      raise NotImplementedError
    end

    # [{foreign_id:, symbol:, type:, executed_at:, quantity:, value:}]
    def transactions(connection, account, since: nil)
      raise NotImplementedError
    end

    # [{foreign_id:, name:, financial_institution:, financial_institution_slug:,
    #   disabled_at:}] — every connection this connector's credentials can see,
    # for discovering what to create Connection rows for.
    def authorizations
      raise NotImplementedError
    end

    # [{code:, mic_code:, name:, suffix:, timezone:, start_time:, close_time:}]
    def exchanges
      []
    end
  end
end
