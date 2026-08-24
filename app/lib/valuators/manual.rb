module Valuators
  # No source at all: the value is whatever was last typed into the asset form,
  # and it stands until someone types another one. This is the fallback for
  # anything nothing can be scraped for — a boat, a painting, a stake in a
  # private company — and the escape hatch for when a scraper stops working.
  class Manual < Base
    # Nothing to fetch. The Quote carrying a hand-entered price is created with
    # that price already set, so Quote#fetch returns before ever asking here;
    # reaching this method means there is no value on hand yet.
    def price(asset)
      nil
    end

    # A number someone entered doesn't expire, and asking for it again is not a
    # thing that can happen.
    def quote_ttl
      nil
    end

    def refresh_interval
      nil
    end
  end
end
