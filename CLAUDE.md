# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Dough Board is a Rails 8.1 app (Ruby 3.4.8, SQLite) for tracking personal assets/liabilities. It pulls live quotes and historical data from [AlphaVantage](https://www.alphavantage.co/) and scrapes stock split history from splithistory.com.

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

AlphaVantage API key lives in encrypted credentials (needs `config/master.key`):

```bash
bin/rails credentials:edit      # add alpha_vantage.api_key (see config/credentials.yml.sample)
```

## Architecture

**StandardAPI-driven controllers.** Controllers/routing use the `standardapi` gem, not stock Rails scaffolding. Routes are declared with `standard_resources :transactions` (see `config/routes.rb`), and `ApplicationController` includes `StandardAPI::Controller` + `StandardAPI::AccessControlList`. Controller-permitted attributes are defined in ACL modules under `app/controllers/acl/` (e.g. `TransactionACL#attributes`), **not** via `params.permit`. `ApplicationController#create` is monkey-patched to redirect on HTML requests while keeping JSON `render :show` behavior. Note: standardapi requires the `pg` gem at load time (it patches the PostgreSQL adapter) even though this app connects via sqlite3 — hence `pg` in the Gemfile.

**External data via singletons.** Two service objects use the `Singleton` + `method_missing` class-delegation pattern so they're called as `AlphaVantage.quote(sym)` / `SplitHistoryScraper.splits(sym)`:
- `config/initializers/alpha_vantage.rb` — REST client for quotes (`GLOBAL_QUOTE`), crypto rates (`CURRENCY_EXCHANGE_RATE`), and daily time series. Strips the AlphaVantage `"01. symbol"` numeric key prefixes.
- `config/initializers/split_history_scraper.rb` — Nokogiri HTML scraper returning `[split_date, ratio]` pairs.

**Model layer does the fetching automatically.** The `type` column on `Asset` and `Transaction` is a plain string, not Rails STI — both models set `self.inheritance_column = nil` to disable STI while keeping a `type` attribute (`Asset` type ∈ stock/fund/crypto, `Transaction` type ∈ buy/sale).
- `Quote` has a `before_validation :fetch` that lazily populates `price`/`quoted_at` from AlphaVantage. `Asset#current_quote` returns a cached quote if one is <24h old, otherwise **creates a new Quote** (triggering a fetch). Reading `asset.price` can therefore hit the network.
- `Asset#load_splits` caches scraped splits for 24h via the `splits_updated_at` timestamp.
- `Transaction` auto-creates its `Asset` from a virtual `symbol` accessor (`before_validation :create_asset`) and computes `adjusted_quantity` (`before_save`) by multiplying `quantity` through every split that occurred after `executed_at`.

**Portfolio aggregation** lives in `TransactionsController#index`: it folds buys/sales into per-symbol quantities using `adjusted_quantity`, then values each holding against the asset's current price.

**Assets** use the modern Rails pipeline: Propshaft serves fingerprinted assets from `app/assets/builds`, `jsbundling-rails` drives esbuild for JS (`esbuild.config.mjs`), and `tailwindcss-rails` compiles `app/assets/tailwind/application.css` → `app/assets/builds/tailwind.css` (Tailwind v4). Both build steps run automatically on `bin/rails test`/`assets:precompile`; use `bin/dev` (`Procfile.dev`) to watch them in development. The former Condenser/SassC/`uniform-ui` stack is gone — the layout links `tailwind.css` and the bundled `boot.js`, and the old uniform `Tooltip` is now a small vanilla `data-tooltip` handler in `boot.js`.
