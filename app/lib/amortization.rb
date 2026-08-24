# A fixed-rate loan, worked out from the terms it was written on.
#
# A mortgage's balance is not something anyone has to look up: it follows from
# the principal, the rate, the term and the start date, and the only thing that
# changes between one month and the next is how many payments have been made.
# So a mortgage is kept the way a car's value is — computed rather than fetched
# — and the balance an account reports is whatever this says it is today.
#
# A plain value object, built from the json on `accounts.loan_terms`. It
# refuses to be built from terms that don't describe a loan (see .from), so
# everything downstream can assume the numbers are usable.
class Amortization

  # The keys this reads off accounts.loan_terms. AccountACL permits exactly
  # these, so a form post can't write arbitrary json onto an account.
  KEYS = %w(principal annual_rate term_months started_on).freeze

  # 50 years. Longer than any real mortgage, and short enough that a typo in the
  # term field is caught rather than compounded 12,000 times.
  MAX_TERM_MONTHS = 600

  attr_reader :principal, :annual_rate, :term_months, :started_on

  # Returns an Amortization, or nil when the terms don't describe a loan — an
  # account half filled in, a rate of 400%, a term of nothing. Callers treat nil
  # as "there is no balance to report", which is what keeps a half-entered
  # account from claiming its mortgage is paid off.
  def self.from(terms)
    terms = (terms || {}).stringify_keys
    principal = terms["principal"].to_f
    annual_rate = terms["annual_rate"].to_f
    term_months = terms["term_months"].to_i
    started_on = parse_date(terms["started_on"])

    return nil if principal <= 0
    return nil unless term_months.between?(1, MAX_TERM_MONTHS)
    return nil unless annual_rate >= 0 && annual_rate < 100
    return nil if started_on.nil?

    new(principal: principal, annual_rate: annual_rate,
        term_months: term_months, started_on: started_on)
  end

  def self.parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue Date::Error, TypeError
    nil
  end

  def initialize(principal:, annual_rate:, term_months:, started_on:)
    @principal = principal
    @annual_rate = annual_rate
    @term_months = term_months
    @started_on = started_on
  end

  # The rate is entered the way anyone says it — "6.25" for 6.25% a year.
  def monthly_rate
    annual_rate / 100.0 / 12.0
  end

  # The level payment that retires the principal over the term. An interest-free
  # loan divides rather than amortizes; the formula below divides by the rate.
  def monthly_payment
    return (principal / term_months).round(2) if monthly_rate.zero?

    growth = (1 + monthly_rate)**term_months
    (principal * monthly_rate * growth / (growth - 1)).round(2)
  end

  # Payments are due on the same day of each month, the first one a month after
  # the start date, so this counts monthly anniversaries that have passed. A
  # start date of the 31st counts a payment on the 28th of February as not yet
  # made, which is off by at most a few days once a year.
  def payments_made(on: Date.current)
    months = (on.year - started_on.year) * 12 + (on.month - started_on.month)
    months -= 1 if on.day < started_on.day
    months.clamp(0, term_months)
  end

  # What's still owed. Derived from the schedule rather than accumulated, so it
  # can be asked for any date — including ones in the past, which is what gives
  # a paydown curve for free.
  def balance(on: Date.current)
    made = payments_made(on: on)
    # A lender rounds the level payment to the cent and adjusts the final one to
    # close the loan — over 360 payments that rounding is worth a dollar or two,
    # which would otherwise be left owed forever.
    return 0.0 if made >= term_months
    return [principal - (principal / term_months) * made, 0.0].max.round(2) if monthly_rate.zero?

    growth = (1 + monthly_rate)**made
    remaining = principal * growth - monthly_payment * ((growth - 1) / monthly_rate)
    # The level payment is rounded to the cent, so the last one leaves a few
    # cents either side of zero. Owing -$0.03 is not a thing.
    [remaining, 0.0].max.round(2)
  end

  def payoff_on
    started_on >> term_months
  end

  # Total interest over the life of the loan, for the summary on the account
  # page — the number that makes a rate mean something.
  def total_interest
    (monthly_payment * term_months - principal).round(2)
  end

end
