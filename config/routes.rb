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
      get  :legacy_bulk_generate           # legacy flow, step 1: fund/sector/tag filter + turbo preview
      post :legacy_bulk_generate_options   # legacy flow, step 2: render options (1st hit) or run generation (2nd hit)
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
    sessions: 'users/sessions'
  }

  resources :users do
    get 'search', on: :collection
    get 'no_password_login', on: :collection
    # Authenticated admin/support impersonation. Distinct from no_password_login (the email
    # self-login link): login_as requires the acting admin to be logged in and authorized, so
    # there is no bearer token in a URL that could be leaked and replayed anonymously.
    post 'login_as', on: :member
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
    get 'redirect_to_subdomain', on: :collection
  end

  resource :two_factor, only: %i[new create], controller: 'users/two_factor' do
    get  :select_mode           # choose WhatsApp vs Authenticator
    post :select_mode, action: :select_mode_post
    get  :enroll                # authenticator mode: QR code setup
    post :verify_enrollment     # authenticator mode: confirm TOTP code
    get  :enroll_whatsapp       # whatsapp mode: confirm phone + send test code
    post :verify_whatsapp_enrollment # whatsapp mode: verify test code
    post :send_whatsapp
    get  :backup_codes
  end

  post "/internal/sync/users",         to: "users_sync#upsert"
  post "/internal/sync/users/disable", to: "users_sync#disable"
  post "/internal/sync/users/digest",  to: "users_sync#digest" # optional reconciliation

  post "/ses_notifications", to: "ses_notifications#create"
  post "/grafana/alert", to: "grafana_alerts#alert"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"

  resources :user_guides, only: [:index]
  get 'user_guides/*id', to: 'user_guides#show', as: :user_guide, format: false
  resources :release_notes, only: %i[index show], constraints: { id: %r{[^/]+} }
  resources :features, only: [:index]
  get 'features/*id', to: 'features#show', as: :feature, format: false

  get 'outlook_addin/taskpane', to: 'outlook_addin#taskpane'
  # Opened in an Office dialog (a top-level window, so the session cookie works there)
  # to mint the bearer token the task pane authenticates with.
  get 'outlook_addin/oauth_start', to: 'outlook_addin#oauth_start'
  # Same purpose for the Gmail add-on, which opens this in a browser tab and receives the
  # token back through Apps Script's usercallback.
  get 'gmail_addin/oauth_start', to: 'gmail_addin#oauth_start'
  # Legacy session-authenticated endpoints for the old Outlook task pane. Superseded by
  # the token-authenticated /api/v1/mail/* API below, which both add-ins now use.
  get 'outlook_addin/investors', to: 'outlook_addin#investors'
  resources :email_matches, only: [:create]
  resources :incoming_emails do
    post :sendgrid, on: :collection
  end

  # Shared mail add-in API — Outlook task pane and Gmail add-on both call these.
  # Bearer-token authenticated via Doorkeeper; no session cookie is involved.
  namespace :api do
    namespace :v1 do
      namespace :mail do
        post 'match', to: 'matches#create'
        get 'owners', to: 'owners#index'
        resources :filings, only: %i[create destroy] do
          post :attachments, on: :member
        end
        # Browsers preflight the cross-origin calls the Outlook task pane makes.
        match '*path', to: 'base#preflight', via: :options
      end
    end
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
