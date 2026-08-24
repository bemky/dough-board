require "sidekiq/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # Sidekiq's dashboard: queue depth, retries, and what the workers are doing.
  # It's a Rack app, so ApplicationController's require_login never runs for it
  # — LoggedInConstraint is that check. Referenced through a lambda so the
  # constant resolves per request rather than when routes are drawn, which keeps
  # it reloadable in development.
  constraints ->(request) { LoggedInConstraint.matches?(request) } do
    mount Sidekiq::Web => "/jobs", as: :jobs
  end

  # A failed constraint otherwise falls through to a routing error, so a logged
  # out owner would get a bare 404 with nothing to act on. Send them to the same
  # login form as the rest of the app, and back here once they're through.
  match "/jobs(/*path)", via: :all, to: redirect(status: 302) { |_params, request|
    Rails.application.routes.url_helpers.login_path(redirect_to: request.fullpath)
  }

  root "assets#index"

  get "assets", to: "assets#index", as: :assets
  # Propshaft serves /assets/*, so member routes can't live under that prefix —
  # they'd 404 in the asset middleware before reaching the controller. The
  # helpers are still edit_asset_path/asset_path.
  # Declared by hand rather than through `resources`, and ahead of it so
  # "holdings/new" isn't read as an id: `assets` is already taken as a route
  # name by the index above, which is the name `resources ... only: [:create]`
  # would want for POST /holdings.
  get "holdings/new", to: "assets#new", as: :new_asset
  post "holdings", to: "assets#create", as: :create_asset
  resources :assets, only: [:edit, :update], path: "holdings"
  get "quotes/:symbol", to: "assets#quote", as: :asset_quote, constraints: {symbol: /[^\/]+/}

  post "connections/discover", to: "connections#discover", as: :discover_connections
  # Plaid has no list of a client_id's connections to discover: each one is made
  # by running Plaid Link in the browser, which is what these two serve — the
  # page that opens Link, and where its one-time token comes back to. Declared
  # ahead of standard_resources so "link" isn't read as a connection id.
  get "connections/link", to: "connections#link", as: :link_connections
  post "connections/link", to: "connections#complete_link", as: :complete_link_connections
  standard_resources :connections do
    post :sync, on: :member
  end

  post "transactions/import", to: "transactions#import", as: :import_transactions
  standard_resources :transactions
  standard_resources :positions
  standard_resources :accounts do
    resources :transactions, only: [:index]
    resources :positions, only: [:index]
  end
end
