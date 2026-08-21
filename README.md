# Dough Board
A Rails app for tracking persona assets and liabilities

Uses (AlphaVantage)[https://www.alphavantage.co/] to pull in quotes and historical data.

## Setup
Add AlphaVantage API key to `credentials.yml.enc`

    alpha_vantage:
        api_key: ######

## Deployment

Deploys via [Capistrano](https://capistranorb.com/). Requires SSH access to the
`dough-board` deploy user on the target server and a `config/credentials.yml`
matching `config/credentials.yml.sample` linked into shared config on the server
(see `config/deploy.rb`).

    bundle exec cap production deploy
