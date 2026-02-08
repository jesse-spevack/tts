Rails.application.routes.draw do
  root "pages#home"

  namespace :admin do
    resource :analytics, only: [ :show ], controller: "analytics"
  end

  resources :episodes, only: [ :index, :new, :create, :show, :destroy ]

  # Magic link authentication
  get "auth", to: "sessions#new", as: :auth

  # Login page
  get "login", to: "logins#new", as: :login

  # Redirect old sign-in path to root
  get "session/new", to: redirect("/")
  get "sign_in", to: redirect("/")

  # Static pages
  get "terms", to: "pages#terms"
  get "privacy", to: "pages#privacy"
  get "privacy-01" => "pages#privacy_01"
  get "privacy-02" => "pages#privacy_02"
  get "404-01" => "pages#error_404_01"
  get "404-02" => "pages#error_404_02"
  get "home-01" => "pages#home_01"
  get "home-02" => "pages#home_02"
  get "home-03" => "pages#home_03"
  get "pricing-01" => "pages#pricing_01"
  get "pricing-02" => "pages#pricing_02"
  get "pricing-03" => "pages#pricing_03"
  get "about-01" => "pages#about_01"
  get "about-02" => "pages#about_02"
  get "about-03" => "pages#about_03"
  get "how-it-sounds", to: "pages#how_it_sounds"
  get "help/add-rss-feed", to: "pages#add_rss_feed", as: :help_add_rss_feed
  get "help/extension", to: "pages#extension_help", as: :help_extension

  # Feed proxy
  get "/feeds/:podcast_id", to: "feeds#show", constraints: { podcast_id: /podcast_\w+\.xml/ }

  namespace :api do
    namespace :internal do
      resources :episodes, only: [ :update ]
    end

    namespace :v1 do
      resource :extension_token, only: [ :create ]
      resources :episodes, only: [ :create ]
      resources :extension_logs, only: [ :create ]
    end
  end

  resource :session
  resource :settings, only: [ :show, :update ]

  namespace :settings do
    resource :email_episodes, only: [ :create, :destroy ]
    resource :email_token, only: [ :create ]
    resource :extensions, only: [ :show, :destroy ]
  end

  # Browser extension auth callback
  namespace :extension do
    resource :connect, only: [ :show ], controller: "connect"
  end

  # Billing
  get "pricing", to: redirect("/#pricing")
  resource :upgrade, only: [ :show ], controller: "upgrades"
  resource :billing, only: [ :show ], controller: "billing"
  resource :portal_session, only: [ :create ]
  get "checkout", to: "checkout#show"
  post "checkout", to: "checkout#create"
  get "checkout/success", to: "checkout#success"
  get "checkout/cancel", to: "checkout#cancel"
  post "webhooks/stripe", to: "webhooks#stripe"
  post "webhooks/resend/inbound", to: "webhooks/resend#inbound"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Marketing preview (dev tool for inspecting partials)
  get "marketing-preview", to: "marketing_preview#index", as: :marketing_preview
  post "marketing-preview/refine", to: "marketing_preview#refine", as: :marketing_preview_refine

  # Test helpers (only available in development/test)
  if Rails.env.local?
    get "test/magic_link_token/:email", to: "test_helpers#magic_link_token", constraints: { email: /[^\/]+/ }
    post "test/create_user", to: "test_helpers#create_user"
  end
end
