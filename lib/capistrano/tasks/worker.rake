# Sidekiq workers run as instances of a systemd template unit
# (dough-board-worker@0.service, @1, ...). Set :worker_instances in deploy.rb to
# match however many the server has enabled.
set :worker_instances, fetch(:worker_instances, [0])

namespace :worker do
  desc "Start the Sidekiq workers"
  task :start do
    on roles(:app) do
      fetch(:worker_instances).each do |instance|
        execute "sudo systemctl start #{fetch(:application)}-worker@#{instance}.service"
      end
    end
  end

  desc "Stop the Sidekiq workers"
  task :stop do
    on roles(:app) do
      fetch(:worker_instances).each do |instance|
        execute "sudo systemctl stop #{fetch(:application)}-worker@#{instance}.service"
      end
    end
  end

  desc "Restart the Sidekiq workers so they pick up the new release"
  task :restart do
    on roles(:app) do
      fetch(:worker_instances).each do |instance|
        unit = "#{fetch(:application)}-worker@#{instance}.service"
        # A unit that hit systemd's start-rate limit stays failed and ignores
        # restart until it's reset, so clear that first. This must not abort a
        # deploy — but it must not vanish either: without a NOPASSWD sudoers
        # rule for reset-failed specifically, sudo asks for a password no one
        # can type and the safety net quietly stops existing. Say so instead.
        execute "sudo -n systemctl reset-failed #{unit} || " \
                "echo 'WARNING: reset-failed on #{unit} was refused — add a NOPASSWD " \
                "sudoers rule for it (see BUILD.md), or a rate-limited worker will " \
                "stay dead through a deploy that reports success.' >&2"
        execute "sudo systemctl restart #{unit}"
      end
    end
  end
end

after "deploy:finished", "worker:restart"
