module Valuators
  # A car's value, worked out rather than looked up. Kelley Blue Book has no
  # self-serve API and its number is behind a mileage-and-condition form rather
  # than a page that can be read, so the alternative to paying a vehicle-data
  # vendor is to model the curve: value decays at a fixed rate a year from what
  # was paid, and never falls below a floor.
  #
  # It costs nothing, can't be rate-limited, and can't break — and for a car a
  # few years old it lands within a few percent of KBB. When it drifts, override
  # it by typing the real number into the asset form; that writes a quote the
  # same way any other source does.
  class Depreciation < Base
    DEFAULT_ANNUAL_RATE = 15.0

    # What's left at the bottom of the curve, as a share of what was paid. A car
    # with 200,000 miles on it is still worth something, and an exponential
    # decay left alone approaches zero.
    DEFAULT_RESIDUAL_SHARE = 0.10

    DAYS_PER_YEAR = 365.25

    def keys
      [
        {name: :purchase_price, label: "Purchase price", type: :number,
         hint: "What was paid for it, before tax and fees."},
        {name: :purchased_on, label: "Purchase date", type: :date,
         hint: nil},
        {name: :annual_rate, label: "Annual depreciation (%)", type: :number,
         hint: "Share of remaining value lost each year. Defaults to #{DEFAULT_ANNUAL_RATE.to_i}%, about right for a mainstream car."},
        {name: :residual_value, label: "Floor value", type: :number,
         hint: "The curve never goes below this. Defaults to #{(DEFAULT_RESIDUAL_SHARE * 100).to_i}% of the purchase price."}
      ]
    end

    def price(asset)
      settings = asset.valuation_key || {}
      paid = settings["purchase_price"].to_f
      purchased_on = parse_date(settings["purchased_on"])
      return nil if paid <= 0 || purchased_on.nil?

      rate = rate_for(settings)
      return nil if rate.nil?

      # A date in the future is a typo, not a car that hasn't lost value yet;
      # either way the answer is what was paid.
      years = [(Date.current - purchased_on).to_f / DAYS_PER_YEAR, 0.0].max
      floor = floor_for(settings, paid)

      [paid * ((1 - rate)**years), floor].max.round(2)
    end

    # Deterministic and local, so there's nothing to gain from recomputing it
    # every half hour — but a point a day keeps the value history smooth.
    def refresh_interval
      1.day
    end

    # The last computed value stands until the next daily run replaces it.
    def quote_ttl
      nil
    end

    private

    # Entered as a percentage, because "15" is how anyone says this. Outside
    # 0–100 there is no curve to draw, so refuse rather than invent one.
    def rate_for(settings)
      percent = settings["annual_rate"].presence&.to_f || DEFAULT_ANNUAL_RATE
      return nil unless percent > 0 && percent < 100
      percent / 100.0
    end

    def floor_for(settings, paid)
      entered = settings["residual_value"].presence&.to_f
      return entered if entered && entered >= 0
      paid * DEFAULT_RESIDUAL_SHARE
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      Date.parse(value.to_s)
    rescue Date::Error, TypeError
      nil
    end
  end
end
