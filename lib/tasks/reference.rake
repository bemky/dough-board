namespace :reference do

  # Fills the exchanges table from the provider's own list, which covers every
  # venue positions actually arrive carrying — including the crypto ones (COIN,
  # KRAK) that have no MIC at all. Exchanges change roughly never, so this runs
  # on demand rather than on a schedule; run it once at setup.
  desc "Refresh the exchanges table from a connector's reference data"
  task exchanges: :environment do
    Connectors.names.each do |connector|
      rows = Connectors.for(connector).exchanges
      next if rows.empty?

      created = updated = 0
      rows.each do |attributes|
        next if attributes[:code].blank? || attributes[:name].blank?
        exchange = find_exchange(attributes) || Exchange.new
        created += 1 if exchange.new_record?
        updated += 1 unless exchange.new_record?
        exchange.update!(attributes)
      end
      puts "#{connector}: #{rows.length} exchange(s) — #{created} created, #{updated} updated"
    end
  end

  # Matched on MIC before code: the same venue can be listed under a different
  # short code than the one already on hand (NYSE Arca is ARCA here and ARCX
  # elsewhere), and matching on code alone would file it as a second exchange
  # with the same MIC — which then makes MIC lookups ambiguous.
  def find_exchange(attributes)
    by_mic = Exchange.find_by(mic_code: attributes[:mic_code]) if attributes[:mic_code].present?
    by_mic || Exchange.find_by(code: attributes[:code])
  end

end
