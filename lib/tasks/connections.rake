namespace :connections do

  # Appends a point to every connected institution's position history. Run on a
  # schedule (see config/schedule.rb) alongside positions:derive, which does the
  # same for accounts fed by their transactions.
  desc "Sync every active connection"
  task sync: :environment do
    as_of = Time.current
    Connection.active.find_each do |connection|
      ConnectionJob.perform_later(connection, as_of: as_of)
    end
  end

  # Picks up connections made on the provider's own site. A SnapTrade Personal
  # key has no in-app connection portal, so this is how they arrive here.
  desc "Create a Connection for every authorization a connector can see"
  task discover: :environment do
    Connectors.names.each do |connector|
      connections = Connection.discover!(connector)
      puts "#{connector}: #{connections.length} connection(s)"
    end
  end

end
