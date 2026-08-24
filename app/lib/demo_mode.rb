# Shows the app to somebody without showing them what's in it.
#
# Prices are public and stay exactly as they are; what's private is *how much*
# is held, so every holding's quantity is rendered as a random 5-20% of the real
# one. Scaling the quantity rather than the value is what keeps a screen
# believable: the page's JS recomputes value as quantity x price as fresh quotes
# land, so a doctored value alone would be corrected back to the real one within
# a second of the page loading.
#
# The factor is **derived, not drawn**. A random number per render would make
# the same holding a different size on every page load, and the portfolio total,
# the account total and the row it came from would each disagree. Digesting the
# symbol against a per-installation seed instead gives a factor that is stable
# across pages, requests and restarts, and unguessable without the seed — so a
# holding shown at 12% stays at 12% for as long as the demo lasts, and every
# screen showing that asset agrees about it.
#
# Two things this deliberately is not:
#
# - It is not a rounding of the truth. Each holding gets its own factor, so the
#   proportions between holdings move too — reading one number off a screenshot
#   tells you nothing about any other.
# - It is not a data change. This is a display layer and nothing else: positions
#   are still derived, synced and amortized from the real figures, by jobs that
#   never run inside a request and so never see #enabled? at all. Nothing scaled
#   here is ever written back.
module DemoMode

  # A holding shows as somewhere in this band of what's really held. Wide enough
  # that the shape of the portfolio isn't preserved, narrow enough that the
  # numbers still look like numbers somebody would hold.
  MINIMUM = 0.05
  MAXIMUM = 0.20

  class << self

    # On for everybody, for the whole process, when DEMO_MODE is set — the way a
    # deploy that exists to be shown off is run. Otherwise it's whatever the
    # current request turned on for itself (see ApplicationController).
    def enabled?
      forced? || Current.demo.present?
    end

    # Whether the environment has pinned it on, in which case there's nothing
    # for the header's toggle to switch off.
    def forced?
      ActiveModel::Type::Boolean.new.cast(ENV["DEMO_MODE"]).present?
    end

    # The number to show in place of `number`, or `number` itself when the demo
    # is off. `key` is what makes two screens agree — pass the same thing for
    # the same holding, which in practice means the asset's symbol.
    def scale(number, key)
      return number if number.nil? || !enabled?
      number * factor(key)
    end

    # A stable fraction in MINIMUM..MAXIMUM for `key`.
    def factor(key)
      MINIMUM + fraction(key) * (MAXIMUM - MINIMUM)
    end

    private

    # The first 8 hex digits of the digest, as a 0..1 fraction. Eight is plenty:
    # the band it lands in is 15 percentage points wide, so a billion steps
    # across it is already far finer than anything rendered.
    def fraction(key)
      digest = Digest::SHA256.hexdigest("#{seed}:#{key}")
      digest[0, 8].to_i(16).fdiv(0xffffffff)
    end

    # Per installation, and not on show anywhere: knowing the seed and the
    # symbol is knowing the factor, and knowing the factor turns a demo screen
    # back into the real portfolio. DEMO_SEED is there to re-roll every factor
    # at once (a new demo, a new set of numbers) without touching anything else.
    def seed
      ENV["DEMO_SEED"].presence || Rails.application.secret_key_base
    end

  end
end
