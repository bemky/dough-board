# Generates the crontab entry below via the `whenever` gem
# (https://github.com/javan/whenever). Preview it locally with:
#
#   bundle exec whenever
#
# Deploy applies it with:
#
#   bundle exec whenever --update-crontab dough-board --set environment=production
set :output, "log/cron.log"

every 30.minutes do
  rake "quotes:refresh_all"
end

# Repricing the holdings against those quotes, and adding a point to the value
# history. Offset from the refresh above so it reads warm quotes.
every 1.hour, at: 5 do
  rake "positions:derive"
end

# The same point in the history, for accounts an institution feeds rather than
# transactions. Offset again so the two aren't competing for the worker.
every 1.hour, at: 10 do
  rake "connections:sync"
end
