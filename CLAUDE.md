# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Dough Board is a Rails 8.1 app (Ruby 3.4.8, SQLite) for tracking personal assets/liabilities. It pulls live quotes from [Finnhub](https://finnhub.io/) (via the `finnhub_ruby` gem) and scrapes stock split history from splithistory.com.

## Commands

```bash
bin/setup                       # install deps, prepare DB (first-time setup)
bin/rails server                # run the app
bin/rails db:migrate            # apply migrations
bin/rails test                  # run all tests (Minitest)
bin/rails test test/models/transaction_test.rb          # single file
bin/rails test test/models/transaction_test.rb:12       # single test by line
bin/rails test:system           # Capybara/Selenium system tests
```

```bash
bin/dev                         # run web + JS watcher + CSS watcher (Procfile.dev)
```

JS is bundled separately from Ruby: `npm install` pulls esbuild (`package.json`), and `esbuild.config.mjs` bundles `app/assets/javascripts/boot.js` → `app/assets/builds/boot.js`.

## Setup

Credentials live in an **unencrypted, environment-keyed** `config/credentials.yml`
(gitignored; no `master.key`/`.enc`). Copy the template and fill in your values:

```bash
cp config/credentials.yml.sample config/credentials.yml   # then edit
```

The file is keyed by environment (`development:`, `test:`), and Rails selects the
current env's section automatically. Each section holds `secret_key_base` (generate
one with `bin/rails secret`) and `finnhub.api_key`. This override is wired up
by `ext/active_support/encrypted_configuration.rb` (patches `ActiveSupport::EncryptedConfiguration`
to read a plaintext, env-namespaced file), required early in `config/application.rb`
alongside `config.credentials.content_path = Rails.root.join("config", "credentials.yml")`.

## Architecture

**StandardAPI-driven controllers.** Controllers/routing use the `standardapi` gem, not stock Rails scaffolding. Routes are declared with `standard_resources :transactions` (see `config/routes.rb`), and `ApplicationController` includes `StandardAPI::Controller` + `StandardAPI::AccessControlList`. Controller-permitted attributes are defined in ACL modules under `app/controllers/acl/` (e.g. `TransactionACL#attributes`), **not** via `params.permit`. `ApplicationController#create` is monkey-patched to redirect on HTML requests while keeping JSON `render :show` behavior. Note: standardapi requires the `pg` gem at load time (it patches the PostgreSQL adapter) even though this app connects via sqlite3 — hence `pg` in the Gemfile.

**External data via singletons.** Two service objects use the `Singleton` + `method_missing` class-delegation pattern so they're called as `Finnhub.quote(sym)` / `SplitHistoryScraper.splits(sym)`:
- `config/initializers/finnhub.rb` — thin wrapper over the `finnhub_ruby` gem's `DefaultApi#quote` (a hand-written client whose `quote` returns a Hash); `Finnhub.quote(sym)` returns the current price (the `c` field), or `nil` when Finnhub has no data (an unknown symbol returns `c=0`) or the request fails (e.g. rate limited, raising `FinnhubRuby::FinnhubAPIException`). Finnhub only prices crypto for exchange-prefixed pairs, so `Asset#quote_symbol` maps crypto symbols to `BINANCE:<SYM>USDT` (stocks/funds pass through unchanged); `Quote#fetch` requests `asset.quote_symbol`.
- `config/initializers/split_history_scraper.rb` — Nokogiri HTML scraper returning `[split_date, ratio]` pairs.

**Model layer does the fetching automatically.** The `type` column on `Asset` and `Transaction` is a plain string, not Rails STI — both models set `self.inheritance_column = nil` to disable STI while keeping a `type` attribute (`Asset` type ∈ stock/fund/crypto, `Transaction` type ∈ buy/sale).
- `Quote` has a `before_validation :fetch` that lazily populates `price`/`quoted_at` from Finnhub. When Finnhub returns no price (unknown symbol, rate limit), `fetch` does `throw :abort` so the blank Quote is **not** persisted. `Asset#current_quote` returns a cached quote if one is <24h old, otherwise **creates a new Quote** (triggering a fetch). Reading `asset.price` can therefore hit the network.
- `Asset#load_splits` caches scraped splits for 24h via the `splits_updated_at` timestamp.
- `Transaction` auto-creates its `Asset` from a virtual `symbol` accessor (`before_validation :create_asset`) and computes `adjusted_quantity` (`before_save`) by multiplying `quantity` through every split that occurred after `executed_at`.

**Portfolio aggregation** lives in `TransactionsController#index`: it folds buys/sales into per-symbol quantities using `adjusted_quantity`, then values each holding against the asset's current price.

**Assets** use the modern Rails pipeline: Propshaft serves fingerprinted assets from `app/assets/builds`, `jsbundling-rails` drives esbuild for JS (`esbuild.config.mjs`), and `tailwindcss-rails` compiles `app/assets/tailwind/application.css` → `app/assets/builds/tailwind.css` (Tailwind v4). Both build steps run automatically on `bin/rails test`/`assets:precompile`; use `bin/dev` (`Procfile.dev`) to watch them in development. The former Condenser/SassC/`uniform-ui` stack is gone — the layout links `tailwind.css` and the bundled `boot.js`, and the old uniform `Tooltip` is now a small vanilla `data-tooltip` handler in `boot.js`.
