require "openssl"
require "base64"
require "csv"
require "json"
require "net/http"
require "uri"

# Export filled crypto orders from the Robinhood Crypto Trading API as a CSV in
# the same shape as the "executed trades" export that TransactionsController#import
# consumes.
#
#   bin/rails robinhood:crypto_csv                    # writes tmp/robinhood_crypto_trades.csv
#   bin/rails robinhood:crypto_csv[/path/to/out.csv]
#
# Credentials (config/credentials.yml, under the current environment):
#
#   robinhood:
#     api_key: rh-api-...
#     private_key: <base64 Ed25519 seed>   # the private key half of the pair you
#                                          # registered; ENV ROBINHOOD_PRIVATE_KEY also works
namespace :robinhood do
  desc "Export filled Robinhood crypto orders to a CSV in the import format"
  task :crypto_csv, [:path] => :environment do |_t, args|
    path = args[:path].presence || Rails.root.join("tmp", "robinhood_crypto_trades.csv").to_s

    orders = RobinhoodCrypto.new.orders
    filled = orders.select { |o| o["state"] == "filled" }

    CSV.open(path, "w") do |csv|
      csv << %w[fill_date symbol asset_type side quantity avg_price gross_amount fees net_cash order_type source order_id]
      filled.sort_by { |o| o["created_at"].to_s }.each { |o| csv << RobinhoodCrypto.row_for(o) }
    end

    puts "Wrote #{filled.size} filled crypto orders (of #{orders.size} total) to #{path}"
  end
end

# Minimal signed client for the Robinhood Crypto Trading API. Every request is
# authenticated with an Ed25519 signature over
# "<api_key><timestamp><path><METHOD><body>", base64-encoded in x-signature.
class RobinhoodCrypto
  class Error < StandardError; end

  BASE_URL = "https://trading.robinhood.com".freeze
  ORDERS_PATH = "/api/v1/crypto/trading/orders/".freeze

  def initialize(api_key: nil, private_key: nil)
    creds = Rails.application.credentials.robinhood || {}
    @api_key = api_key || creds[:api_key]
    seed = private_key || ENV["ROBINHOOD_PRIVATE_KEY"] || creds[:private_key]

    raise Error, "Missing robinhood.api_key in credentials" if @api_key.blank?
    raise Error, "Missing robinhood.private_key in credentials (or ROBINHOOD_PRIVATE_KEY)" if seed.blank?

    @key = OpenSSL::PKey.new_raw_private_key("ED25519", Base64.decode64(seed))
  end

  # Walks the cursor-paginated orders endpoint and returns every crypto order.
  def orders
    results = []
    path = "#{ORDERS_PATH}?limit=100"

    while path
      body = get(path)
      results.concat(Array(body["results"]))
      nxt = body["next"]
      path = nxt.present? ? URI.parse(nxt).request_uri : nil
    end

    results
  end

  # Maps one API order onto a row of the import CSV. Quantities/prices come from
  # the fills when present (an order can fill in several executions at different
  # prices) and fall back to the order-level rollup otherwise.
  def self.row_for(order)
    executions = Array(order["executions"])

    quantity = if executions.any?
      executions.sum { |e| e["quantity"].to_d }
    else
      order["filled_asset_quantity"].to_d
    end

    gross = if executions.any?
      executions.sum { |e| e["quantity"].to_d * e["effective_price"].to_d }
    else
      quantity * order["average_price"].to_d
    end

    avg_price = quantity.zero? ? 0.to_d : gross / quantity
    side = order["side"] == "sell" ? "sell" : "buy"
    fill_date = (executions.last&.dig("timestamp") || order["updated_at"] || order["created_at"]).to_s[0, 10]

    [
      fill_date,
      # "BTC-USD" -> "BTC"; Asset#quote_symbol re-maps crypto to BINANCE:<SYM>USDT.
      order["symbol"].to_s.split("-").first,
      "crypto",
      side,
      quantity.to_s("F"),
      avg_price.round(8).to_s("F"),
      gross.round(2).to_s("F"),
      "0",
      # Buys are cash out, sales are cash in. Robinhood crypto has no explicit
      # commission field (cost is in the spread), so net is just ±gross.
      (side == "buy" ? -gross.round(2) : gross.round(2)).to_s("F"),
      order["type"],
      "user",
      order["id"]
    ]
  end

  private

  def get(path)
    uri = URI.parse("#{BASE_URL}#{path}")
    request = Net::HTTP::Get.new(uri)
    headers(path, "GET", "").each { |k, v| request[k] = v }

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Robinhood #{path} returned #{response.code}: #{response.body}"
    end

    JSON.parse(response.body)
  end

  def headers(path, method, body)
    timestamp = Time.now.to_i
    signature = @key.sign(nil, "#{@api_key}#{timestamp}#{path}#{method}#{body}")

    {
      "x-api-key" => @api_key,
      "x-timestamp" => timestamp.to_s,
      "x-signature" => Base64.strict_encode64(signature),
      "Content-Type" => "application/json"
    }
  end
end
