namespace :plaid do

  # Plaid's sandbox will mint an Item for a test institution without a browser,
  # so the whole path — exchange, accounts, holdings, activity, pruning — can be
  # exercised against the real API before a production connection is spent on
  # it. Production Items are what a Plaid plan is capped by; the sandbox is free
  # and unlimited.
  #
  #   bin/rails plaid:sandbox                  # Vanguard, the investments fixture
  #   bin/rails plaid:sandbox[ins_109508]      # First Platypus, the liabilities one
  #   bin/rails plaid:sandbox[ins_109512]      # some other test institution
  #
  # The institution decides what can be asked of it — see #sandbox_public_token,
  # which narrows the products to the ones it lists.
  #
  # Refuses to run unless the credentials on hand are sandbox ones, so it can't
  # quietly burn a real connection.
  desc "Connect a Plaid sandbox institution and sync it, no browser needed"
  task :sandbox, [:institution_id] => :environment do |_task, args|
    connector = Connectors.for("plaid")
    institution_id = args[:institution_id].presence || "ins_115616"

    abort "Plaid credentials are missing." unless connector.configured?
    abort "plaid.environment is #{connector.environment}, not sandbox." unless connector.environment == "sandbox"

    connection = Connection.link!("plaid", connector.sandbox_public_token(institution_id))
    puts "Connected #{connection.label} (item #{connection.foreign_id})"

    # Inline rather than enqueued: the point is to see it work, and to see it
    # fail here rather than in a worker log.
    ConnectionJob.perform_now(connection)
    connection.reload

    puts "Synced at #{connection.synced_at}"
    connection.accounts.each do |account|
      puts "  #{account.label} (#{account.number}) — #{account.current_positions.count} position(s), " \
        "#{account.transactions.count} transaction(s)"
      account.current_positions.includes(:asset).each do |position|
        puts "      #{position.asset.symbol.ljust(24)} #{position.units} @ #{position.price} = #{position.value}"
      end
    end
  end

  # Sandbox Items still count as Items. Cleaning up keeps a test run from
  # leaving connections behind, and exercises the release path that a real
  # delete depends on.
  desc "Delete every Plaid connection and release its Item"
  task teardown: :environment do
    Connection.where(connector: "plaid").find_each do |connection|
      label = connection.label
      connection.destroy!
      puts "Removed #{label}"
    end
  end

end
