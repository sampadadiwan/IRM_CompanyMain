Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'

  resources :portfolio_reports do
    resources :portfolio_report_templates, shallow: true
    member do
      post :clone
      post :suggest_sections    # AI-suggested section names + instructions
    end
    collection do
      get  :bulk_generate       # form: select portcos + template
      post :bulk_generate       # submit: queue a draft job per portco
    end
  end

  resources :portfolio_report_drafts do
    member do
      patch :approve
      patch :approve_and_export        # approve then immediately queue export
      patch :reopen                    # revert approved/exported → review for further editing
      post  :export
      get   :preview                   # styled HTML preview of the Word doc layout
      patch :update_kpi_cell           # inline KPI cell edit
      patch :update_section            # inline narrative section edit
      post  :regenerate_section        # re-run LLM for a single section
    end
  end

  resources :portfolio_report_extracts do
    member do
      get :generate_tear_sheet
      patch :update_slides_content
    end
  end

  resources :excused_investors

  resources :rm_mappings

  mount ActionCable.server => '/cable'

  resources :support_client_mappings do
    member do
      patch :switch
      patch :revert
    end
  end

  draw :admin
  draw :fund
  draw :secondary
  draw :startup
  draw :misc
  draw :core
  draw :ai

  devise_for :users, controllers: {
    # We no longer allow users to register on their own
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: 'users/confirmations',
    sessions: 'users/sessions'
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
    get 'cross_site_link', on: :member

    get 'cross_site_login', on: :collection
  end

  post "/internal/sync/users",         to: "users_sync#upsert"
  post "/internal/sync/users/disable", to: "users_sync#disable"
  post "/internal/sync/users/digest",  to: "users_sync#digest" # optional reconciliation

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"

  resources :user_guides, only: %i[index show]
  resources :release_notes, only: %i[index show], constraints: { id: /[^\/]+/ }

  get 'outlook_addin/taskpane', to: 'outlook_addin#taskpane'
  get 'outlook_addin/investors', to: 'outlook_addin#investors'
  resources :email_matches, only: [:create]
  resources :incoming_emails do
    post :sendgrid, on: :collection
  end

  if Rails.env.test?
    # This will just return a 200 OK to any GET on /ws/socket.io
    get '/ws/socket.io', to: proc { [200, {}, ['']] }
    get "/*path", to: proc { [204, {}, [""]] }, constraints: ->(req) { req.path.end_with?(".map") }
  end

  get 'ai', to: 'ow#index'

  use_doorkeeper_openid_connect
  use_doorkeeper

  get '/.well-known/oauth-authorization-server', to: 'oauth_metadata#show'
  get '/.well-known/oauth-protected-resource', to: 'oauth_metadata#protected_resource'
end
