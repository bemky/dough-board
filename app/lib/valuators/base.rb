module Valuators
  # What every valuator has to answer. #price is the whole job — a Float, or nil
  # when this source has nothing to say — and the rest describes how the app
  # should treat it: how long an answer stands, how often to ask again, whether
  # a web request may wait on it, and what the asset form has to collect.
  #
  # Follows the Singleton + class-delegation pattern used by Connectors::Base,
  # so callers write `Valuators::Depreciation.price(asset)`.
  class Base
    include Singleton

    # **kwargs is load-bearing here for the same reason it is on
    # Connectors::Base: without it Ruby 3 folds a call's keywords into a
    # positional Hash.
    def self.method_missing(method, *args, **kwargs, &block)
      instance.__send__(method, *args, **kwargs, &block)
    end

    def self.respond_to_missing?(method, include_private = false)
      instance.respond_to?(method, include_private) || super
    end

    # The asset's current value per unit, or nil when this source can't answer
    # (an unknown symbol, a listing that's gone, settings not filled in yet).
    def price(asset)
      raise NotImplementedError
    end

    # How long an answer stands as "the current price". Nil means it never goes
    # stale: a house scraped last week is still the best number anyone has, and
    # letting it expire would blank the holding out rather than improve it.
    # Finnhub's 24 hours is the original behaviour, kept.
    def quote_ttl
      24.hours
    end

    # How often `quotes:refresh_all` should ask again. Zero means every run,
    # which is what a stock wants; nil means never, which is what a value typed
    # in by hand wants.
    def refresh_interval
      0.seconds
    end

    # What this valuator needs stored on assets.valuation_key, as
    # [{name:, label:, type:, hint:}]. The asset form renders a field per entry
    # and the controller permits exactly these keys.
    def keys
      []
    end

    # The name the asset form shows for this source.
    def label
      self.class.name.demodulize.titleize
    end

    # Whether the app can use this source at all. One it has no credentials for
    # is one the form shouldn't offer.
    def configured?
      true
    end
  end
end
