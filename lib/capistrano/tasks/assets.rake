namespace :assets do
  desc "Precompile assets"
  task :precompile do
    on roles(:app, select: :primary) do
      within release_path do
        execute :npm, "install --production"
        execute :bundle, "exec rails assets:precompile"
      end
    end
  end
end

after "deploy:migrate", "assets:precompile"
