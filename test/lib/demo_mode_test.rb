require "test_helper"

class DemoModeTest < ActiveSupport::TestCase

  test "off, a number is its own number" do
    assert_equal 100.0, DemoMode.scale(100.0, "SCTY")
    assert_not DemoMode.enabled?
  end

  test "on, a holding shows as 5-20% of what's held" do
    Current.set(demo: true) do
      assert DemoMode.enabled?

      # Every symbol lands inside the band, whichever way its digest falls.
      %w[SCTY AAPL BTC USD DEBT:HOME_LOAN FUND:TITAN-FLAGSHIP].each do |symbol|
        scaled = DemoMode.scale(1000.0, symbol)
        assert_operator scaled, :>=, 1000.0 * DemoMode::MINIMUM
        assert_operator scaled, :<=, 1000.0 * DemoMode::MAXIMUM
      end
    end
  end

  test "a symbol keeps its factor, so two screens agree about a holding" do
    Current.set(demo: true) do
      assert_equal DemoMode.scale(500.0, "SCTY"), DemoMode.scale(500.0, "SCTY")
      # And it's a factor, not an offset: the same holding split over two
      # accounts adds back up to the whole one.
      assert_in_delta DemoMode.scale(300.0, "SCTY") + DemoMode.scale(200.0, "SCTY"),
        DemoMode.scale(500.0, "SCTY"), 0.0001
    end
  end

  test "holdings are not scaled by one shared factor, so proportions move too" do
    Current.set(demo: true) do
      factors = %w[SCTY AAPL BTC TSLA VOO].map { |symbol| DemoMode.factor(symbol) }
      assert_equal factors.uniq, factors
    end
  end

  test "a debt keeps its sign, and nothing scales to a holding that isn't there" do
    Current.set(demo: true) do
      assert_operator DemoMode.scale(-4000.0, "DEBT:HOME_LOAN"), :<, 0
      assert_nil DemoMode.scale(nil, "SCTY")
    end
  end

  test "the environment can pin it on for a whole deployment" do
    assert_not DemoMode.forced?

    with_env("DEMO_MODE" => "true") do
      assert DemoMode.forced?
      # Nothing had to ask for it: no request, no session, still on.
      assert DemoMode.enabled?
    end
  end

  test "the seed can be re-rolled without touching anything else" do
    Current.set(demo: true) do
      before = DemoMode.factor("SCTY")
      with_env("DEMO_SEED" => "a different demo") do
        assert_not_equal before, DemoMode.factor("SCTY")
      end
      assert_equal before, DemoMode.factor("SCTY")
    end
  end

  private

  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

end
