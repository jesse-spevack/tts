Rails.application.routes.draw do
  root "pages#home"

  resources :episodes, only: [ :index, :new, :create, :show ]

  # Magic link authentication
  get "auth", to: "sessions#new", as: :auth

  # Redirect old sign-in path to root
  get "session/new", to: redirect("/")
  get "sign_in", to: redirect("/")

  # Static pages
  get "terms", to: "pages#terms"
  get "how-it-sounds", to: "pages#how_it_sounds"
  get "help/add-rss-feed", to: "pages#add_rss_feed", as: :help_add_rss_feed

  namespace :api do
    namespace :internal do
      resources :episodes, only: [ :update ]
    end
  end

  resource :session
  resource :settings, only: [ :show, :update ]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
