Rails.application.routes.draw do
  resources :investments
  resources :viewed_bies

  resources :dashboard_widgets do
    get 'dashboard', on: :collection
  end

  resources :ai_checks do
    post 'run_checks', on: :collection
    get 'run_checks', on: :collection
  end

  resources :ai_rules
  resources :rm_mappings
  resources :key_biz_metrics
  resources :incoming_emails
  resources :doc_questions
  # mount Rswag::Ui::Engine => '/api-docs'
  # mount Rswag::Api::Engine => '/api-docs'
  mount ActionCable.server => '/cable'
  resources :support_client_mappings
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
    post 'whatsapp_webhook', on: :collection
    get 'welcome', on: :collection
    get 'set_persona', on: :collection
    post 'reset_password', on: :collection
    post 'accept_terms', on: :collection
    get 'chat', on: :collection
    post 'chat', on: :collection
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"

  post 'incoming_emails/sendgrid', to: 'incoming_emails#sendgrid'
end
