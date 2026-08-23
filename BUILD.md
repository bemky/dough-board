# BUILD.md — Server Setup Checklist (Arch Linux)

Checklist for provisioning a new Arch Linux host (or a fresh app slot on an
existing shared host) to serve this app. App name used throughout: `dough-board`.
Substitute your actual app name/user/port where relevant.

## 1. System user

- [ ] Create a dedicated system user for the app: `useradd -m -d /srv/dough-board -s /bin/bash dough-board`
- [ ] Add the user's SSH `authorized_keys` (either manually, or via whatever
      key-sync mechanism the host uses) so `cap deploy` can log in as this user.

## 2. Directory layout (Capistrano)

- [ ] `/srv/dough-board/releases/`
- [ ] `/srv/dough-board/shared/`
- [ ] `/srv/dough-board/repo/` (created automatically by `cap deploy` on first run)
- [ ] Confirm `config/deploy.rb` `deploy_to` and `ssh_options[:user]` match the
      user/path chosen above.
- [ ] Confirm `config/deploy.rb` sets `:branch` explicitly if the default
      branch isn't `master` (Capistrano defaults to `master`).

## 3. Ruby / Bundler

- [ ] Install a system Ruby matching the version pinned in the `Gemfile`
      (`ruby "x.y.z"`). Either install that exact version or update the
      Gemfile pin to match what's available on the host — pick one source of
      truth and keep them in sync.
- [ ] Confirm a C toolchain (`gcc`, `make`, linker libs like `libgcc_s`) is
      present and working — native gem extensions (nokogiri, bigdecimal, etc.)
      will fail to compile otherwise.
- [ ] `bundler` version is auto-installed per the `BUNDLED WITH` line in
      `Gemfile.lock` — no manual step needed, but make sure the committed
      lockfile is actually up to date with the Gemfile (all groups, including
      the `deploy` group: capistrano, capistrano-rails, capistrano-bundler,
      sshkit, etc.)

## 4. Database

- [ ] PostgreSQL installed and running.
- [ ] Create the app's DB role and database (name/user typically match the
      Rails app name, e.g. `dough_board_production`).
- [ ] `shared/config/database.yml` (linked file, not committed) — set
      adapter/host/username/password/database for `production:`.

## 5. Credentials

- [ ] `shared/config/credentials.yml` (linked file, not committed) — this app
      reads plaintext env-keyed credentials rather than Rails' encrypted
      `credentials.yml.enc` (see `ext/active_support/encrypted_configuration.rb`).
      Needs at minimum:
      - `production.secret_key_base` (generate with `openssl rand -hex 64`)
      - any third-party API keys the app needs (e.g. `finnhub.api_key`)
- [ ] Confirm `config/deploy.rb`'s `linked_files`/`linked_dirs` list includes
      both `config/credentials.yml` and `config/database.yml`.

## 6. Redis (for Sidekiq)

- [ ] Install a Redis-compatible server. Arch no longer packages `redis`
      (license change) — use `valkey` instead (drop-in compatible, same
      default port 6379).
- [ ] `systemctl enable --now valkey.service`
- [ ] Confirm Sidekiq's `REDIS_URL` (or the default `redis://localhost:6379/0`)
      points at wherever this instance is actually running.

## 7. systemd units

Create per-app units (mirror an existing app's units, renaming):
- [ ] `dough-board.target` — umbrella target for the app
- [ ] `dough-board-app.socket` — Puma socket activation
- [ ] `dough-board-app.service` — Puma app server
- [ ] `dough-board-workers.target` — umbrella target for background workers
- [ ] `dough-board-worker@.service` — templated Sidekiq worker unit (start
      instances as `dough-board-worker@0.service`, `@1`, etc.)
- [ ] `systemctl enable dough-board-app.service` (+ socket/target) for
      boot-time auto-start.
- [ ] `systemctl enable dough-board-worker@0.service` for each worker
      instance you want running.

### The worker unit must not pass `-q` or `-C`

This app's queues are declared in `config/sidekiq.yml`, which `sidekiq` loads on
its own. Keeping them there means the queue list travels with the release
instead of living in a server-side file nobody looks at.

- [ ] Confirm `ExecStart` runs plain `bundle exec sidekiq` with **no** `-q` and
      **no** `-C`.

Worth spelling out because mirroring another app's unit is how this goes wrong:
if that app ran several queues its unit likely carries `-q '*'`, and `*` is
taken as a **literal queue name**, not a wildcard. The failure is silent and
looks nothing like a queue problem — the worker registers, heartbeats, reports
`busy: 0`, never errors, and jobs pile up untouched:

```ruby
Sidekiq::Stats.new.enqueued          # climbing
Sidekiq::Stats.new.processed         # 0
Sidekiq::Stats.new.failed            # 0
Sidekiq::ProcessSet.new.size         # 1 — a worker really is alive
```

The one command that settles it, on the server:

```bash
valkey-cli monitor | grep -i brpop | head -5
```

`"brpop" "queue:default"` is healthy. `"brpop" "queue:*"` means the worker is
polling a queue that will never exist.

## 8. sudoers (deploy user needs to restart its own services)

Capistrano's deploy task runs `sudo systemctl restart ...` as the deploy
user. Add **NOPASSWD** rules for exactly the units it touches — including
the **instantiated** worker unit name, not just the workers target:

```
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dough-board.target
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dough-board.target
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dough-board-app.socket
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dough-board-app.socket
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dough-board-app.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dough-board-app.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl status dough-board-app.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dough-board-workers.target
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dough-board-workers.target
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dough-board-worker@*.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dough-board-worker@*.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop dough-board-worker@*.service
dough-board ALL=(ALL) NOPASSWD: /usr/bin/systemctl status dough-board-worker@*.service
```

- [ ] Add rules to `/etc/sudoers` (or a file under `/etc/sudoers.d/`).
- [ ] **If using `/etc/sudoers.d/`**, confirm `/etc/sudoers` actually contains
      a `#includedir /etc/sudoers.d` line — without it, drop-in files are
      silently never read even though `visudo -c` reports them as valid.
- [ ] Validate with `visudo -c -f <file>` before installing, `visudo -c`
      after.
- [ ] Test as the actual deploy user before trusting it:
      `sudo -u dough-board sudo -n systemctl restart dough-board-app.service`

## 9. nginx + SSL

- [ ] Site config proxying to the Puma socket, with an HTTP block (port 80)
      handling the Let's Encrypt ACME challenge + redirect to HTTPS, and an
      HTTPS block (port 443) terminating TLS and proxying upstream.
- [ ] Obtain a cert via certbot (webroot method) for the domain.
- [ ] `/etc/letsencrypt/renewal/<domain>.conf` — set `renew_hook`/`post_hook`
      to `systemctl reload nginx` so renewals actually take effect.
- [ ] Confirm `certbot.timer` is enabled for automatic renewal.

## 10. DNS

- [ ] Point the domain's A/AAAA record at this host.

## 11. First deploy

- [ ] `cap deploy` from a machine with push access and the deploy key.
- [ ] Confirm `current` symlink is created and points at the new release.
- [ ] Confirm app responds over HTTPS with a valid cert.
- [ ] Confirm worker unit(s) are `active (running)`, not crash-looping.
- [ ] Confirm the workers are actually *consuming*, not merely running — an
      idle worker on the wrong queue looks identical to a healthy one from
      `systemctl status`. From `cap production console`:

      ```ruby
      require "sidekiq/api"
      Sidekiq::Stats.new.processed     # must climb once anything is enqueued
      Sidekiq::ProcessSet.new.map { |p| p["queues"] }   # expect ["default"]
      ```

## 12. Reading logs

Rails and Sidekiq both log to stdout under systemd, so output lands in the
journal — **not** in `log/production.log`.

```bash
sudo journalctl -u dough-board-app.service -n 200 -f        # web
sudo journalctl -u 'dough-board-worker@*' -n 200 -f         # every worker
sudo journalctl -u 'dough-board-*' -n 200 -f                # both, interleaved
sudo journalctl -u 'dough-board-worker@*' -p err --no-pager # failures only
```

- [ ] Add the deploy user to the `systemd-journal` group so reading logs doesn't
      need `sudo` at all: `usermod -aG systemd-journal dough-board` (takes
      effect on next login). The sudoers rules above cover `systemctl` only —
      they deliberately don't grant `journalctl`, and group membership is the
      narrower way to allow reads.

`cap production log` tails the **app** unit specifically; for jobs, use the
worker commands above.
