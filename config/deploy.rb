# config valid for current version and patch releases of Capistrano
lock "~> 3.19"

set :application, "dough-board"
set :repo_url, "git@github.com:bemky/dough-board.git"

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/srv/dough-board"

# Persist the sqlite databases, uploaded files, and unencrypted credentials
# across releases (see config/credentials.yml.sample and
# ext/active_support/encrypted_configuration.rb for the credentials setup).
append :linked_files, "config/credentials.yml"
append :linked_dirs, "log", "storage", "tmp/pids", "tmp/cache", "tmp/sockets"

set :keep_releases, 5

set :ssh_options, {
  user: "dough-board",
}

set :default_env, {
  "RACK_ENV" => fetch(:stage),
  "RAILS_ENV" => fetch(:stage),
}
