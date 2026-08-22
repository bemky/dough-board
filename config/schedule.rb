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
