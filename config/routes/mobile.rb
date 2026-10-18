# LP mobile app (openspec/changes/lp-mobile-app).
#
# Drawn before `resources :users` in config/routes.rb so /users/mobile_devices and
# /users/mobile_handoff are not taken as users#show with id "mobile_devices".

# The phone API — bearer-token, cookie-less, versioned (design card ④)
namespace :api do
  namespace :mobile do
    namespace :v1 do
      resource :session, only: %i[create destroy] do
        post :verify
        post :resend
        post :refresh
      end
      resource :me, only: :show, controller: :me do
        patch :push_preferences
      end
      # Only what the website has no JSON for. Calls, distributions, commitments, documents and
      # notifications are read from the website's own .json endpoints with the same token.
      resource :home, only: :show, controller: :home
      resources :documents, only: :index
      resource :device, only: :update
      resources :web_handoffs, only: :create
    end
  end
end

# Website: Profile › Devices (design card ③)
scope :users, module: :users, as: :users do
  resources :mobile_devices, only: %i[index destroy]
  # Profile › API tokens (funds-json-api-hardening card ①)
  resources :api_tokens, only: %i[index create destroy]
  # Where the app's one-time website link lands (design card ⑦)
  get :mobile_handoff, to: "mobile_handoffs#show"
end
