namespace :quotes do
  desc "Fetch and cache a fresh quote for every asset (run on a schedule via config/schedule.rb)"
  task refresh_all: :environment do
    Asset.find_each do |asset|
      # Dollars, held or owed, are worth a dollar; there is nothing to ask.
      next if asset.face_value?

      # How often a source is worth asking again is the source's own business:
      # Finnhub every run, a depreciation curve once a day, a value someone
      # typed in never. Without this the half-hourly schedule would recompute
      # settled numbers 48 times a day and write a quote each time.
      unless asset.quote_due?
        puts "#{asset.symbol}: still current"
        next
      end

      quote = Quote.create(asset: asset)
      puts "#{asset.symbol}: #{quote.persisted? ? quote.price : "no quote available"}"
    end
  end
end
