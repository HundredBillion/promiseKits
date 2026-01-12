require_relative '../lib/constraints/fitness_kit_slug_constraint'

Rails.application.routes.draw do
  # Fitness kit order pages - only matches if slug exists in database
  # These can now be ANYWHERE in the routes file thanks to the database constraint!
  # Moved to the TOP to prove they don't need special positioning anymore!
  get '/:slug', to: 'orders#new', as: :fitness_kit_order,
                constraints: FitnessKitSlugConstraint
  post '/:slug', to: 'orders#create', as: :create_fitness_kit_order,
                 constraints: FitnessKitSlugConstraint

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  # Order confirmation page
  resources :orders, only: [:show]
end
