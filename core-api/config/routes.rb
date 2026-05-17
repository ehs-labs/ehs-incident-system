Rails.application.routes.draw do
  # Health check (no auth, no DB) — used by docker/k8s probes
  get  "/healthz", to: ->(_) { [200, {}, ["ok"]] }

  # Sidekiq dashboard (protected in production via Pundit/Devise)
  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq"

  # OpenAPI / Swagger UI (rswag) — useful in dev
  mount Rswag::Ui::Engine  => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      # ----- Auth -------------------------------------------------------
      devise_scope :user do
        post   "auth/login",   to: "auth/sessions#create"
        delete "auth/logout",  to: "auth/sessions#destroy"
        post   "auth/signup",  to: "auth/registrations#create"
        post   "auth/refresh", to: "auth/sessions#refresh"
        post   "auth/password",to: "auth/passwords#create"
        patch  "auth/password",to: "auth/passwords#update"
        get    "auth/confirm", to: "auth/confirmations#show"
      end

      # ----- Profile (current user) ------------------------------------
      resource :me, only: %i[show update], controller: "me" do
        patch :password, on: :collection
        post  :link_telegram, on: :collection
      end

      # ----- Domain ----------------------------------------------------
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
        member do
          post "transitions", to: "corrective_actions#transition"
        end
      end
      resources :notifications, only: %i[index update] do
        collection do
          post :mark_all_read
        end
      end
      get "dashboard", to: "dashboard#show"

      # ----- Admin -----------------------------------------------------
      namespace :admin do
        resources :users do
          member do
            post :lock
            post :unlock
            post :resend_invitation
          end
          collection do
            post :invite
          end
        end
        resources :sites
        resource  :settings, only: %i[show update]
      end

      # ----- Internal (service-to-service) -----------------------------
      namespace :internal do
        # Service-account JWT only — see Pundit policy
        get "users/:id/notification_addresses", to: "users#notification_addresses"
      end
    end
  end
end
