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

    # How a connection to this service gets made. The two are exclusive in
    # practice: a service either lets us read what its credentials are already
    # connected to (SnapTrade, where the connecting happens on its own site), or
    # it hands out a per-connection secret through a browser flow we have to run
    # ourselves (Plaid Link). The connections page asks these before offering
    # either button.
    def discoverable?
      true
    end

    def linkable?
      false
    end

    # A linkable connector's two halves: a token that authorizes one run of the
    # provider's browser flow, and the exchange of what that flow returns for
    # the attributes of a Connection — `credentials` among them, which is the
    # whole reason the column exists.
    def link_token(connection = nil)
      raise NotImplementedError
    end

    def connect!(public_token)
      raise NotImplementedError
    end

    # Releases the provider's side of a connection being deleted, for services
    # that count them against a plan. Returns whether anything was released.
    def disconnect!(connection)
      false
    end

    # Whether the app has credentials for this service at all. A connector
    # without them is one nothing should offer to connect through.
    def configured?
      true
    end
  end
end
