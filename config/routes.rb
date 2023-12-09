Rails.application.routes.draw do
  resources :custom_notifications
  resources :reports
  resources :ci_track_records
  resources :ci_widgets
  resources :ci_profiles
  draw :admin
  draw :fund
  draw :secondary
  draw :startup
  draw :misc
  draw :core

  devise_for :users, controllers: {
    # We no longer allow users to register on their own
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: 'users/confirmations'
  }

  resources :users do
    get 'search', on: :collection
    get 'no_password_login', on: :collection
    post 'magic_link', on: :collection
    get 'welcome', on: :collection
    get 'set_persona', on: :collection
    post 'reset_password', on: :collection
    post 'accept_terms', on: :collection
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"
end
