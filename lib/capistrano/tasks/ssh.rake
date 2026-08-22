desc "SSH into an application server"
task :ssh do
  host = roles(:app).sample
  command = "exec $SHELL -l"
  puts command if fetch(:log_level) == :debug

  exec "ssh -l #{fetch(:ssh_options)[:user]} #{host.hostname} -p #{host.port || 22} -t '#{command}'"
end

desc "SSH into an application server and bring up a Rails console"
task :console do
  host = roles(:app).sample
  command = "cd ~/current && RAILS_ENV=#{fetch(:stage)} bundle exec rails c"
  puts command if fetch(:log_level) == :debug

  exec "ssh -l #{fetch(:ssh_options)[:user]} #{host.hostname} -p #{host.port || 22} -t '#{command}'"
end

desc "SSH into an application server and tail logs"
task :log do
  host = roles(:app).sample
  # Rails logs to stdout under systemd, so the journal — not log/production.log
  # — is where output actually lands. sudo because the unit is system-scoped.
  command = "sudo journalctl -u #{fetch(:application)}-app.service -n 200 -f"
  puts command if fetch(:log_level) == :debug

  exec "ssh -l #{fetch(:ssh_options)[:user]} #{host.hostname} -p #{host.port || 22} -t '#{command}'"
end
