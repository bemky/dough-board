namespace :positions do

  # Appends a new point to every manual account's position history, repriced
  # against whatever quotes are currently cached. Run on a schedule (see
  # config/schedule.rb); accounts fed by a connector are refreshed by their own
  # sync instead.
  desc "Snapshot every manual account's positions"
  task derive: :environment do
    as_of = Time.current
    Account.find_each do |account|
      next unless account.manual?
      DerivePositionsJob.perform_later(account, as_of: as_of)
    end
  end

end
