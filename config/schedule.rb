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
