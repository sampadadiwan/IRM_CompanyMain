Rails.application.routes.draw do
  resources :account_entries
  resources :fund_units
  resources :fund_ratios
  resources :capital_remittance_payments
  resources :esigns
  resources :signature_workflows
  resources :investor_notice_entries
  resources :investor_notices
  resources :fees
  namespace :admin do
    namespace :paper_trail do
      resources :versions
    end
    resources :investors
    resources :users
    resources :entities
    resources :documents
    resources :investments
    resources :access_rights
    resources :deals
    resources :deal_investors
    resources :deal_activities
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
    resources :funds
    resources :valuations
    resources :capital_calls
    resources :capital_commitments
    resources :capital_distributions
    resources :capital_remittances
    resources :capital_distribution_payments

    # namespace :audited do
    #   resources :audits
    # end

    root to: "investors#index"
  end

  resources :share_transfers
  resources :capital_distribution_payments do
    get 'search', on: :collection
  end
  resources :capital_distributions do
    post 'approve', on: :member
    patch 'redeem_units', on: :member
  end
  resources :capital_remittances do
    patch 'verify', on: :member
    get 'search', on: :collection
    patch 'generate_docs', on: :member
  end
  resources :capital_calls do
    get 'search', on: :collection
    post 'reminder', on: :member
    post 'approve', on: :member
    patch 'generate_docs', on: :member
    patch 'allocate_units', on: :member
  end

  resources :capital_commitments do
    patch 'generate_documentation', on: :member
    patch 'generate_esign_link', on: :member
    get 'search', on: :collection
    get 'report', on: :member
  end

  resources :funds do
    get   'timeline', on: :member
    get   'last', on: :member
    get 'report', on: :member
    get 'generate_calcs', on: :member
  end

  resources :investment_snapshots
  resources :expression_of_interests do
    patch 'approve', on: :member
    patch 'allocate', on: :member
    get   'allocation_form', on: :member
    get 'search', on: :collection
    patch 'generate_documentation', on: :member
    patch 'generate_esign_link', on: :member
  end

  resources :investment_opportunities do
    patch 'toggle', on: :member
    post 'allocate', on: :member
    get 'search', on: :collection
    patch 'send_notification', on: :member
    get 'finalize_allocation', on: :member
  end

  resources :approval_responses do
    patch 'approve', on: :member
  end
  resources :approvals do
    patch 'approve', on: :member
    patch 'send_reminder', on: :member
  end

  resources :investor_kycs do
    get 'search', on: :collection
    put 'toggle_verified', on: :member
  end
  resources :video_kycs do
    get 'search', on: :collection
  end

  get "/health_check/redis_check", to: "health_check#redis_check"
  get "/health_check/db_check", to: "health_check#db_check"
  get "/health_check/elastic_check", to: "health_check#elastic_check"

  resources :reminders
  resources :permissions
  resources :tasks do
    get 'search', on: :collection
    patch 'completed', on: :member
  end
  resources :form_custom_fields
  resources :form_types

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
    get 'new_simulator', on: :collection
  end

  resources :funding_rounds
  resources :payments
  resources :nudges
  resources :import_uploads

  resources :offers do
    patch 'approve', on: :member
    patch 'accept_spa', on: :member
    patch 'allocate', on: :member
    get   'allocation_form', on: :member
    get 'search', on: :collection
    patch 'generate_esign_link', on: :member
  end

  resources :interests do
    patch 'accept_spa', on: :member
    patch 'short_list', on: :member
    patch 'finalize', on: :member
    patch 'allocate', on: :member
    get   'allocation_form', on: :member
    get 'matched_offers', on: :member
  end

  resources :secondary_sales do
    patch 'make_visible', on: :member
    get 'search', on: :collection
    get 'download', on: :member
    patch 'allocate', on: :member
    patch 'generate_spa', on: :member
    patch 'send_notification', on: :member
    get 'spa_upload', on: :member
    get 'lock_allocations', on: :member
    get 'offers', on: :member
    patch 'approve_offers', on: :member
    get 'interests', on: :member
    get 'finalize_offer_allocation', on: :member
    get 'finalize_interest_allocation', on: :member
    get 'payments', on: :member
  end

  resources :holdings do
    get 'search', on: :collection
    post 'employee_calc', on: :collection
    post 'investor_calc', on: :collection
    patch 'cancel', on: :member
    patch 'approve', on: :member
    patch 'emp_ack', on: :member
    post 'approve_all_holdings', on: :collection
  end

  resources :folders do
    get 'download', on: :member
  end

  resources :investor_accesses do
    get 'search', on: :collection
    patch 'approve', on: :member
    patch 'notify_kyc_required', on: :member
    post 'request_access', on: :collection
    post 'upload', on: :collection
  end
  resources :access_rights do
    get 'search', on: :collection
  end
  resources :notifications

  resources :messages do
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
    get 'investor_deals', on: :collection
  end

  resources :notes do
    get 'search', on: :collection
  end

  resources :investors do
    get 'search', on: :collection
  end

  resources :investments do
    get 'search', on: :collection
    get 'history', on: :member
    get 'investor_investments', on: :collection
    post 'recompute_percentage', on: :collection
  end

  resources :adhaar_esigns do
    get 'completed', on: :member
    get 'digio_webhook', on: :collection
  end
  resources :documents do
    patch 'sign', on: :member
    patch 'signed_accept', on: :member
    get 'search', on: :collection
    get 'investor_documents', on: :collection
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
  get '/oauth2callback', to: 'entities#dashboard'

  case Rails.configuration.upload_server
  when :s3
    # By default in production we use s3, including upload directly to S3 with
    # signed url.
    mount Shrine.presign_endpoint(:cache) => "/s3/params"
  when :s3_multipart
    # Still upload directly to S3, but using Uppy's AwsS3Multipart plugin
    mount Shrine.uppy_s3_multipart(:cache) => "/s3/multipart"
  when :app
    # In development and test environment by default we're using filesystem storage
    # for speed, so on the client side we'll upload files to our app.
    mount Shrine.upload_endpoint(:cache) => "/upload"
  end

  require 'sidekiq/web'

  authenticate :user, ->(user) { user.has_cached_role?(:super) } do
    mount Sidekiq::Web => '/sidekiq'
    mount Blazer::Engine, at: "blazer"
  end
end
