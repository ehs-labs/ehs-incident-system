# The Dashboard + Admin slice ships with route additions the developer will
# integrate into config/routes.rb by hand. Until that happens these specs
# need the routes mounted — append them at spec-load time so the suite is
# self-contained.
Rails.application.routes.append do
  namespace :api do
    namespace :v1 do
      resource :me, only: %i[show update], controller: "me" do
        post :telegram_link
      end

      namespace :admin do
        resources :users, only: %i[index show destroy] do
          collection { post :invite }
          member do
            post :lock
            post :unlock
          end
        end
        resources :sites, only: %i[index show create update destroy]
        resource  :settings, only: %i[show update], controller: "settings"
      end
    end
  end
end

Rails.application.reload_routes!
