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

    # Venue spellings of instruments Dough Board already knows by another name.
    # Kraken carries its older listings under ISO-4217-style codes — crypto
    # prefixed X, fiat prefixed Z, and Bitcoin as XBT — so the coin Coinbase
    # reports as BTC arrives as XXBT and becomes a second asset: its own tile,
    # its own cost basis, and no price at all, because Asset#quote_symbol goes
    # on to ask Finnhub for BINANCE:XXBTUSDT.
    #
    # Keyed by the provider's symbol rather than by venue. None of these codes
    # is a real ticker anywhere else, so there is nothing to collide with, and a
    # flat map applies to activity rows too — those don't reliably say which
    # venue they came from. Only the prefixed listings are here: Kraken leaves
    # newer coins alone (XTZ is XTZ), so stripping an X by rule would mangle
    # them.
    SYMBOL_ALIASES = {
      "XBT" => "BTC",
      "XXBT" => "BTC",
      "XDG" => "DOGE",
      "XXDG" => "DOGE",
      "XETC" => "ETC",
      "XETH" => "ETH",
      "XLTC" => "LTC",
      "XMLN" => "MLN",
      "XREP" => "REP",
      "XXLM" => "XLM",
      "XXMR" => "XMR",
      "XXRP" => "XRP",
      "XZEC" => "ZEC",
      "ZAUD" => "AUD",
      "ZCAD" => "CAD",
      "ZEUR" => "EUR",
      "ZGBP" => "GBP",
      "ZJPY" => "JPY",
      "ZUSD" => "USD"
    }.freeze

    # What Dough Board calls the instrument a provider named `symbol`. Applied
    # at the boundary like everything else here, so nothing downstream — assets,
    # positions, quotes, the treemap — ever sees a venue's private spelling.
    def canonical_symbol(symbol)
      return symbol if symbol.blank?
      SYMBOL_ALIASES.fetch(symbol.to_s.upcase, symbol)
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

    # Which side of the balance sheet a link is being made for. Providers show
    # only the institutions that can answer for everything asked of them, and
    # almost none answer for both — so connecting a brokerage and connecting a
    # credit card are two runs of the flow, not one.
    LINK_KINDS = {
      "holdings" => "bank or brokerage",
      "debts" => "card or loan"
    }.freeze

    # A linkable connector's two halves: a token that authorizes one run of the
    # provider's browser flow, and the exchange of what that flow returns for
    # the attributes of a Connection — `credentials` among them, which is the
    # whole reason the column exists.
    def link_token(connection = nil, kind: LINK_KINDS.keys.first)
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
