require "snaptrade"

module Connectors
  # SnapTrade (https://snaptrade.com) brokers read-only connections to
  # brokerages and reports the positions they hold.
  #
  # Authenticated with a **Personal API key** — a client_id and consumer_key that
  # stand for one person's own connections. The Ruby SDK was written for
  # SnapTrade's Commercial flow and makes user_id/user_secret required keyword
  # arguments on every account call; a Personal key has no such user, and the
  # API ignores both. Passing blanks is what satisfies the SDK without inventing
  # a user that doesn't exist.
  class SnapTrade < Base

    # instrument.kind -> Asset#type. "other" (and anything new) maps to nil
    # rather than a guess; the asset still syncs, it just isn't categorized.
    ASSET_TYPES = {
      "stock" => "stock",
      "adr" => "stock",
      "etf" => "fund",
      "mutualfund" => "fund",
      "crypto" => "crypto"
    }.freeze

    # Activity type -> Transaction type. SnapTrade shouts; Dough Board doesn't,
    # and calls a sale a sale.
    TRANSACTION_TYPES = ::Transaction::TYPES.index_by(&:upcase)
      .merge("SELL" => "sale")
      .freeze

    # Every account SnapTrade knows about, across all of this key's connections.
    # `connection` narrows them to the one authorization.
    def accounts(connection)
      client.account_information.list_user_accounts(**user)
        .select { |account| account.brokerage_authorization == connection.foreign_id }
        .map do |account|
          {
            foreign_id: account.id,
            name: account.name,
            number: account.number,
            institution_name: account.institution_name
          }
        end
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    # Balances are reported per currency and Dough Board carries a single cash
    # figure, so only the account's own currency counts. (`account.balance.total`
    # from the accounts list is the account's whole value, positions included —
    # not its cash.)
    def cash(connection, account)
      balances = client.account_information.get_user_account_balance(
        **user, account_id: account.foreign_id
      )
      balance = Array(balances).find { |b| b.currency&.code == CURRENCY }
      balance&.cash
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    def positions(connection, account)
      response = client.account_information.get_all_account_positions(
        **user, account_id: account.foreign_id
      )
      Array(response.results).filter_map do |position|
        instrument = position.instrument
        next unless instrument&.symbol
        {
          symbol: instrument.symbol,
          name: instrument.description,
          type: ASSET_TYPES[instrument.kind],
          # A plain MIC code ("XNAS"), not the exchange's short name.
          exchange_mic: instrument.exchange,
          figi_code: instrument.figi_instrument&.figi_code,
          units: position.units,
          price: position.price,
          # SnapTrade's cost_basis is the average cost of one unit, which is
          # what Dough Board calls average_price — Position#cost_basis is the
          # total, and is derived from it on save.
          average_price: position.cost_basis,
          currency: instrument.currency || "USD"
        }
      end
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    # Walks SnapTrade's pagination rather than taking the first page: the
    # default page size is 1000, and a long-lived account has more.
    def transactions(connection, account, since: nil)
      collected = []
      offset = 0

      loop do
        response = client.account_information.get_account_activities(
          **user,
          account_id: account.foreign_id,
          offset: offset,
          limit: PAGE_SIZE,
          **(since ? {start_date: since.to_date.to_s} : {})
        )
        page = Array(response.data)
        collected.concat(page.filter_map { |activity| transaction_attributes(activity) })

        offset += page.length
        break if page.empty? || offset >= response.pagination&.total.to_i
      end

      collected
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    def authorizations
      client.connections.list_brokerage_authorizations(**user).map do |authorization|
        {
          foreign_id: authorization.id,
          name: authorization.name,
          financial_institution: authorization.brokerage&.name,
          financial_institution_slug: authorization.brokerage&.slug,
          disabled_at: authorization.disabled ? (authorization.disabled_date || Time.current) : nil
        }
      end
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    def exchanges
      client.reference_data.get_stock_exchanges.map do |exchange|
        {
          code: exchange.code,
          mic_code: exchange.mic_code,
          name: exchange.name,
          suffix: exchange.suffix,
          timezone: exchange.timezone,
          start_time: exchange.start_time,
          close_time: exchange.close_time
        }
      end
    rescue ::SnapTrade::ApiError => e
      raise ConnectionError, message_for(e)
    end

    def configured?
      credentials&.try(:client_id).present? && credentials&.try(:consumer_key).present?
    end

    private

    PAGE_SIZE = 1000

    # Dough Board carries one cash figure and values everything in dollars.
    CURRENCY = "USD"

    # The SDK requires these; a Personal API key has no user and the API
    # ignores them.
    def user
      {user_id: "", user_secret: ""}
    end

    def credentials
      Rails.application.credentials.snaptrade
    end

    def client
      @client ||= begin
        raise ConnectionError, "SnapTrade credentials are missing" unless configured?
        configuration = ::SnapTrade::Configuration.new
        configuration.client_id = credentials.try(:client_id)
        configuration.consumer_key = credentials.try(:consumer_key)
        ::SnapTrade::Client.new(configuration)
      end
    end

    def transaction_attributes(activity)
      type = TRANSACTION_TYPES[activity.type.to_s.upcase]
      return unless type
      {
        foreign_id: activity.id,
        symbol: activity.symbol&.raw_symbol || activity.symbol&.symbol,
        type: type,
        executed_at: activity.trade_date || activity.settlement_date,
        quantity: activity.units,
        value: activity.amount
      }
    end

    def message_for(error)
      "#{error.class.name.demodulize}: #{error.message.to_s.gsub(/\s+/, " ").strip.truncate(200)}"
    end

  end
end
