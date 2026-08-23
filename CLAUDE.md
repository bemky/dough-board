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
bin/rails reference:exchanges   # fill the exchanges table (once, after setup)
bin/rails connections:discover  # pick up connections made on the provider's site
bin/rails connections:sync      # sync every active connection now
bin/rails positions:derive      # snapshot accounts fed by their transactions
```

`reference:exchanges` is the **only** writer of the `exchanges` table — migrations create just the two rows the pre-existing `assets.exchange` strings referred to. Run it once at setup, or assets sync with a null exchange until you do.

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

**Connectors** (`app/lib/connectors/`) use the same Singleton + delegation pattern, but as a class hierarchy — `Connectors::Base` declares what any service must answer (`accounts`, `positions`, `cash`, `transactions`, `authorizations`, `exchanges`), and everything above deals in plain hashes so no SDK object or provider field name escapes a subclass. `Connectors.for("snaptrade")` resolves through `Connectors::REGISTRY`. Note `Base.method_missing` takes `**kwargs` — without it Ruby 3 folds a call's keywords into a positional Hash and `transactions(connection, account, since:)` arrives as three positional arguments. (The two initializer singletons above have the same gap; they just never pass keywords.)
- `Connectors::SnapTrade` wraps the official `snaptrade` gem. It authenticates with a **Personal API key** — one person's own connections — which means no user registration and no in-app connection portal: connections are made on SnapTrade's site and picked up by `bin/rails connections:discover`. The gem was written for SnapTrade's Commercial flow and makes `user_id`/`user_secret` required keyword arguments on every account call; a Personal key has no such user and the API ignores both, so the connector passes blanks.
- Live position payloads do **not** match SnapTrade's published docs: a position is `{units, price, cost_basis, currency, instrument}`, where `instrument` is one of `StockInstrument`/`EtfInstrument`/`MutualFundInstrument`/`CryptoInstrument`/`AdrInstrument`/`OtherInstrument` carrying `symbol`, `kind`, `description`, `figi_instrument`, and an `exchange` that is a **plain MIC string** (`"XNAS"`). Two traps: SnapTrade's `cost_basis` is the cost of *one unit* (so it maps to `Position#average_price`, and `Position#cost_basis` — the total — is derived from it), and `Exchange` must be matched on `mic_code` **then** `code`, because crypto venues come back as `COIN`/`KRAK` with a null `mic_code`.

**Model layer does the fetching automatically.** The `type` column on `Asset` and `Transaction` is a plain string, not Rails STI — both models set `self.inheritance_column = nil` to disable STI while keeping a `type` attribute (`Asset` type ∈ stock/fund/crypto/cash, `Transaction` type ∈ `Transaction::TYPES` — the brokerage activity vocabulary, `buy`/`sale`/`dividend`/`fee`/…).
- `Quote` has a `before_validation :fetch` that lazily populates `price`/`quoted_at` from Finnhub. When Finnhub returns no price (unknown symbol, rate limit), `fetch` does `throw :abort` so the blank Quote is **not** persisted. `Asset#current_quote` returns a cached quote if one is <24h old, otherwise **creates a new Quote** (triggering a fetch). Reading `asset.price` can therefore hit the network.
- `Asset#load_splits` caches scraped splits for 24h via the `splits_updated_at` timestamp. It is called from `LoadSplitsJob`, not from a request: saving a transaction never blocks on the scraper.
- `Transaction` auto-creates its `Asset` from a virtual `symbol` accessor (`before_validation :create_asset`) and computes `adjusted_quantity` (`before_save`) by multiplying `quantity` through every split **already on hand** that occurred after `executed_at`. `after_create_commit` then enqueues `LoadSplitsJob` (skipped while `splits_updated_at` is <24h old, so an import of many rows for one symbol queues one job), which rescrapes and force-recomputes `adjusted_quantity` for every transaction against that asset. A transaction is therefore briefly unadjusted between save and job completion. `adjusted_quantity` no longer feeds the portfolio directly — it feeds `Transaction#units`, which `DerivePositionsJob` folds into positions.
- Editing an `Asset` invalidates what its identity implies: `after_update` clears cached `quotes` when `symbol` or `type` changes (both feed `quote_symbol`), and on a `symbol` change also drops `splits` and enqueues `LoadSplitsJob`.
- **Jobs run on Sidekiq in production only** (`config/environments/production.rb` sets `config.active_job.queue_adapter = :sidekiq`); development and test stay on the default in-process adapters so neither needs a Redis. Sidekiq connects to `REDIS_URL`, falling back to `redis://localhost:6379/0`, and reads `config/sidekiq.yml`. **Two queues, weighted 4:1** — `default` for anything a person is waiting on (`ConnectionJob`, `DerivePositionsJob`) and `scrapes` for `LoadSplitsJob`, which fetches splithistory.com one asset at a time and arrives in the thousands after a sync. Weighted rather than strictly ordered so the scrapes still progress without ever being the only thing a worker looks at. `config/sidekiq.yml` must name every queue a job uses or that job is enqueued and never runs — `test/jobs/queues_test.rb` pins that. The worker unit must not pass `-q` or `-C`, or this file stops applying (see `BUILD.md` §7; a stray `-q '*'` once had a worker polling a queue literally named `*` while thousands of jobs sat untouched). Workers are instances of a systemd template unit — `dough-board-worker@0.service`, `@1`, … — restarted after every deploy by `worker:restart` (`lib/capistrano/tasks/worker.rake`); set `:worker_instances` in `config/deploy.rb` if the server enables more than instance 0.
- **Sidekiq's dashboard is mounted at `/jobs`.** It's a Rack app, so it bypasses `ApplicationController` entirely and never runs `before_action :require_login` — `LoggedInConstraint` (`app/lib/logged_in_constraint.rb`) is what stands in, reading the same `session[:logged_in]` the rest of the app sets. The constraint is referenced through a lambda in `config/routes.rb` so the constant resolves per request rather than at draw time, keeping it reloadable in development. A rejected constraint would otherwise fall through to a bare 404, so a catch-all beneath the mount redirects to the login form instead. Rendering the dashboard needs a live Redis, which development and test don't run.

**Portfolio aggregation reads `Position`, not `Transaction`.** A `Position` is one holding as of a moment: `(account, asset, as_of)` is unique, and every row written by a single run shares that run's `as_of`, with the account recording the newest in `accounts.positions_as_of`. That pair is what makes "the current snapshot" a plain equality check (`Position.current`) instead of a window function SQLite would have to emulate, and it's what gives portfolio value over time for free.

- `Position.portfolio` folds any scope into `[{symbol:, asset:, units:, price:, value:}, ...]`. It's a relation-level method, so `Position.current.portfolio` is the whole portfolio and `account.current_positions.portfolio` is one account's. It prices holdings off `asset.cached_price` (falling back to the broker's `position.price`) so the value rendered matches what the page's JS recomputes when it refreshes quotes.
- `AssetsController#index` (the root route) and `Account#portfolio`/`#value` both go through it.
- **`accounts.positions_source` says who writes an account's positions**, and there is no partial ownership — `DerivePositionsJob` rewrites and prunes a whole snapshot, so it either owns an account or doesn't touch it. `transactions` (the default) means the job folds them from the account's own transactions; `manual` means the positions are the record of truth and nothing rewrites them; `connection` means `ConnectionJob` syncs them from the institution. `Account#derives_positions?` is the guard, checked at the top of `DerivePositionsJob`, in `Transaction#derive_account_positions`, and in the `positions:derive` task. Only a `manual` account's positions are editable in the UI (`Position#editable?`), and the position form's account select lists only those accounts. `connection` is not a choice anyone makes — a connector sets it on the accounts it creates, so the account form shows it as text (`Account::SELECTABLE_POSITIONS_SOURCES` is what the select offers).
- **`ConnectionJob`** mirrors `DerivePositionsJob`'s snapshot contract exactly: no `as_of` corrects the current snapshot in place, an `as_of` (from `connections:sync`, hourly at `:10`) appends a history point, and holdings the institution stops reporting are pruned. Failures are recorded on `connections.last_error` for the UI **and** re-raised so the queue records a failure rather than a quiet no-op. Uninvested cash rides along as a position against the `USD` cash asset. A synced account's transactions are upserted too, deduped on the existing `(account_id, foreign_id)` index — they're history to browse, not the source of its holdings.
- Switching an account `transactions` → `manual` **keeps whatever was last derived**, so the holdings already worked out become the starting point for hand maintenance rather than being thrown away. Switching back hands the snapshot to the job again, which rewrites it wholesale on its next run.
- The fold uses `Transaction::UNIT_SIGNS` — a type absent from that table (a dividend, a fee) moves cash, not shares, and must not change the unit count. With no `as_of` the job **corrects the account's current snapshot in place**; the `positions:derive` rake task passes one to append a history point. A transaction's `after_commit` enqueues a run, which `Transaction.without_position_derivation` suppresses for bulk paths like the CSV import (which enqueues one run at the end instead).
- Cash is carried as a position against an `Asset` of type `cash`, worth face value — `Asset#price`/`#cached_price` return `1.0` for it and `Quote#fetch` aborts, so it never reaches Finnhub.

**Assets** use the modern Rails pipeline: Propshaft serves fingerprinted assets from `app/assets/builds`, `jsbundling-rails` drives esbuild for JS (`esbuild.config.mjs`), and `tailwindcss-rails` compiles `app/assets/tailwind/application.css` → `app/assets/builds/tailwind.css` (Tailwind v4). Both build steps run automatically on `bin/rails test`/`assets:precompile`; use `bin/dev` (`Procfile.dev`) to watch them in development. The former Condenser/SassC/`uniform-ui` stack is gone — the layout links `tailwind.css` and the bundled `boot.js`, and the old uniform `Tooltip` is now a small vanilla `data-tooltip` handler in `boot.js`.
