namespace :positions do

  # Appends a new point to the position history of every account this app works
  # out for itself, repriced against whatever quotes are currently cached. Run
  # on a schedule (see config/schedule.rb); accounts fed by a connector are
  # refreshed by their own sync instead, and hand-maintained ones are never
  # rewritten at all.
  desc "Snapshot every account whose positions are derived or amortized"
  task derive: :environment do
    as_of = Time.current
    Account.find_each do |account|
      if account.derives_positions?
        DerivePositionsJob.perform_later(account, as_of: as_of)
      elsif account.amortized_positions?
        # A month between payments, but an hourly point keeps the loan on the
        # same history axis as everything else — the curve steps rather than
        # slopes, which is what a loan actually does.
        AmortizeLoanJob.perform_later(account, as_of: as_of)
      end
    end
  end

end
