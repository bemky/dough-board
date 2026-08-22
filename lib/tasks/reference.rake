namespace :reference do

  # Replaces Exchange::SEEDS' hand-written list with the provider's own, which
  # covers the MIC codes positions actually arrive carrying (COIN, KRAK, and
  # every venue the seed list never anticipated). Exchanges change roughly
  # never, so this runs on demand rather than on a schedule.
  desc "Refresh the exchanges table from a connector's reference data"
  task exchanges: :environment do
    Connectors.names.each do |connector|
      rows = Connectors.for(connector).exchanges
      next if rows.empty?

      rows.each do |attributes|
        next if attributes[:code].blank? || attributes[:name].blank?
        Exchange.find_or_initialize_by(code: attributes[:code]).update!(attributes.except(:code))
      end
      puts "#{connector}: #{rows.length} exchange(s)"
    end
  end

end
