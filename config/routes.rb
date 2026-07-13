Rails.application.routes.draw do
  # Health check for load balancers / platform probes.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resource :settings, only: [ :show, :update ]

      resources :products, only: [ :index ] do
        post :sync, on: :collection
      end

      resources :pricing_runs, only: [ :index, :show, :create ]
      resources :price_changes, only: [ :index ]
    end
  end

  # Single-page app: the React shell handles all non-API, non-asset GET routes
  # via client-side routing.
  root "app#index"
  get "*path", to: "app#index", constraints: lambda { |req|
    req.format.html? &&
      !req.path.start_with?("/api", "/vite", "/up", "/rails")
  }
end
