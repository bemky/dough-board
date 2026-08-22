Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  root "assets#index"

  get "assets", to: "assets#index", as: :assets
  # Propshaft serves /assets/*, so member routes can't live under that prefix —
  # they'd 404 in the asset middleware before reaching the controller. The
  # helpers are still edit_asset_path/asset_path.
  resources :assets, only: [:edit, :update], path: "holdings"
  get "quotes/:symbol", to: "assets#quote", as: :asset_quote, constraints: {symbol: /[^\/]+/}

  post "connections/discover", to: "connections#discover", as: :discover_connections
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
