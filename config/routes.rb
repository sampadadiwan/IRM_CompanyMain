Rails.application.routes.draw do
  resources :holding_audit_trails do
    get 'search', on: :collection
  end
  resources :valuations
  resources :excercises do
    patch 'approve', on: :member
    get 'search', on: :collection
  end

  resources :vestings
  resources :option_pools do
    patch 'approve', on: :member
  end

  resources :aggregate_investments do
    get 'investor_investments', on: :collection
    get 'simple_simulator', on: :collection
  end

  resources :funding_rounds
  resources :payments
  resources :nudges
  resources :import_uploads
  resources :offers do
    patch 'approve', on: :member
    patch 'allocate', on: :member
    get   'allocation_form', on: :member
    get 'search', on: :collection
  end

  resources :secondary_sales do
    patch 'make_visible', on: :member
    get 'search', on: :collection
    get 'download', on: :member
    get 'allocate', on: :member
    get 'notify_allocation', on: :member
    get 'spa_upload', on: :member
  end

  resources :holdings do
    get 'search', on: :collection
    post 'employee_calc', on: :collection
    patch 'cancel', on: :member
    patch 'approve', on: :member
    patch 'emp_ack', on: :member
    post 'approve_all_holdings', on: :collection
    get 'esop_grant_letter', on: :member
  end

  resources :folders
  resources :investor_accesses do
    get 'search', on: :collection
    patch 'approve', on: :member
    post 'request_access', on: :collection
    post 'upload', on: :collection
  end
  resources :access_rights do
    get 'search', on: :collection
  end
  resources :deal_docs
  resources :notifications

  resources :deal_messages do
    post 'mark_as_task', on: :member
    patch 'task_done', on: :member
  end
  resources :deal_activities do
    get 'search', on: :collection
    get 'update_sequence', on: :member
    post 'toggle_completed', on: :member
  end
  resources :deal_investors do
    get 'search', on: :collection
  end
  resources :deals do
    get 'search', on: :collection
    post 'start_deal', on: :member
    post 'recreate_activities', on: :member
    get 'investor_deals', on: :collection
  end

  namespace :admin do
    resources :investors
    resources :users
    resources :entities
    resources :documents
    resources :investments
    resources :access_rights
    resources :deals
    resources :deal_investors
    resources :deal_activities
    resources :deal_docs
    resources :holdings
    resources :offers
    resources :interests
    resources :folders
    resources :investor_accesses
    resources :secondary_sales
    resources :roles
    resources :funding_rounds
    resources :option_pools
    resources :excercises
    namespace :audited do
      resources :audits
    end

    root to: "investors#index"
  end

  resources :notes do
    get 'search', on: :collection
  end

  resources :investors do
    get 'search', on: :collection
  end

  resources :investments do
    get 'search', on: :collection
    get 'investor_investments', on: :collection
  end

  resources :documents do
    get 'search', on: :collection
    get 'investor_documents', on: :collection
  end

  resources :interests do
    patch 'short_list', on: :member
    patch 'finalize', on: :member
  end

  devise_for :users, controllers: {
    registrations: "users/registrations",
    # passwords: "users/passwords",
    confirmations: 'users/confirmations'
  }

  resources :entities do
    get 'search', on: :collection
    get 'investor_entities', on: :collection
    get 'dashboard', on: :collection
    get 'investor_view', on: :member
    post 'delete_attachment', on: :collection
  end

  resources :users do
    get 'search', on: :collection
    get 'welcome', on: :collection
    get 'set_persona', on: :collection
    post 'reset_password', on: :collection
    post 'accept_terms', on: :collection
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"

  require 'sidekiq/web'
  authenticate :user do
    mount Sidekiq::Web => '/sidekiq'
  end
end
