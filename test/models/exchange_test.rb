require "test_helper"

class ExchangeTest < ActiveSupport::TestCase

  test "code is normalized and unique" do
    Exchange.create!(code: "nyse", name: "New York Stock Exchange")
    assert_equal "NYSE", Exchange.last.code

    duplicate = Exchange.new(code: "NYSE", name: "Impostor")
    assert_not duplicate.valid?
  end

  test "an exchange needs a name to be worth having" do
    assert_not Exchange.new(code: "XNAS").valid?
  end

  test "label reads as an exchange, not a row" do
    exchange = Exchange.new(code: "XNAS", name: "Nasdaq Stock Market")
    assert_equal "XNAS - Nasdaq Stock Market", exchange.label
  end

end
