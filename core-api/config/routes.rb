Rails.application.routes.draw do
  # ----- Health & operational --------------------------------------------
  get "/healthz", to: ->(_) { [200, {}, ["ok"]] }

  # Sidekiq dashboard (mount unconditionally in dev/local; protect in production)
  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq"

  # OpenAPI / Swagger UI — only when rswag is loaded (dev/test)
  if defined?(Rswag::Ui) && defined?(Rswag::Api)
    mount Rswag::Ui::Engine  => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  # Devise needs to mount its routes for the User model; we skip the default
  # paths and define our own under /api/v1/auth.
  devise_for :users, skip: :all

  # Top-level named route — Devise's confirmation_instructions mailer template
  # calls `confirmation_url(@resource, ...)`, which expands to the
  # `user_confirmation_url` helper. Defining it here (NOT inside `namespace`)
  # keeps the helper name unprefixed so the template resolves.
  devise_scope :user do
    get "/api/v1/auth/confirm", to: "api/v1/auth/confirmations#show", as: :user_confirmation
  end

  namespace :api do
    namespace :v1 do
      # ----- Auth ------------------------------------------------------
      devise_scope :user do
        post   "auth/login",    to: "auth/sessions#create"
        delete "auth/logout",   to: "auth/sessions#destroy"
        post   "auth/signup",   to: "auth/registrations#create"
        post   "auth/refresh",  to: "auth/sessions#refresh"
        post   "auth/password", to: "auth/passwords#create"
        patch  "auth/password", to: "auth/passwords#update"
        # `auth/confirm` is defined at top-level above (named :user_confirmation)
        # so the Devise mailer template's `confirmation_url` helper resolves.
      end

      # ----- Profile ---------------------------------------------------
      resource :me, only: %i[show update], controller: "me"

      # ----- Domain ---------------------------------------------------
      resources :sites, only: %i[index show create update destroy]
      resources :incidents do
        resources :attachments,        only: %i[index create destroy], shallow: true
        resources :comments,           only: %i[index create],         shallow: true
        resources :corrective_actions, only: %i[index create]
        member do
          post "transitions", to: "incidents#transition"
        end
      end
      resources :corrective_actions, only: %i[show update] do
        member { post "transitions", to: "corrective_actions#update" }
      end
      resources :notifications, only: %i[index update]
      get "dashboard", to: "dashboard#show"
    end
  end
end
