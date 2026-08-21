# Updates the deploy target's crontab from config/schedule.rb after each
# deploy, using the `whenever` gem (https://github.com/javan/whenever).
namespace :whenever do
  desc "Update the crontab from config/schedule.rb"
  task :update_crontab do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:stage) do
          execute :bundle, :exec, :whenever, "--update-crontab", fetch(:application), "--set", "environment=#{fetch(:stage)}"
        end
      end
    end
  end
end

after "deploy:finished", "whenever:update_crontab"
