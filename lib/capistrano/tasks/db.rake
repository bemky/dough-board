namespace :db do
  desc "Download the production database and load it into the current environment"
  task :pull do
    on roles(:db), primary: true do
      remote_path = "#{shared_path}/storage/production.sqlite3"
      local_env = ENV.fetch("RAILS_ENV", "development")
      local_path = File.expand_path("../../../storage/#{local_env}.sqlite3", __dir__)

      if File.exist?(local_path)
        backup_path = "#{local_path}.bak"
        FileUtils.mv(local_path, backup_path)
        puts "Backed up existing #{local_path} to #{backup_path}"
      end

      download! remote_path, local_path
      puts "Downloaded production database to #{local_path} (RAILS_ENV=#{local_env})"
    end
  end
end
