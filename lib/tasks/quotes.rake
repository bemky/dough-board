namespace :quotes do
  desc "Fetch and cache a fresh quote for every asset (run on a schedule via config/schedule.rb)"
  task refresh_all: :environment do
    Asset.find_each do |asset|
      quote = Quote.create(asset: asset)
      puts "#{asset.symbol}: #{quote.persisted? ? quote.price : "no quote available"}"
    end
  end
end
