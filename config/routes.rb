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
  draw :mobile

  devise_for :users, controllers: {
    # We no longer allow users to register on their own
    registrations: "users/registrations",
    passwords: "users/passwords",
    sessions: 'users/sessions',
    # devise-api's /users/tokens/* — refuses two-factor users (lp-mobile-app X7)
    tokens: 'users/tokens'
  }

  resources :users do
    get 'search', on: :collection
    get 'no_password_login', on: :collection
    # Authenticated admin/support impersonation. Distinct from no_password_login (the email
    # self-login link): login_as requires the acting admin to be logged in and authorized, so
    # there is no bearer token in a URL that could be leaked and replayed anonymously.
    post 'login_as', on: :member
    # Clears the user's two-factor METHOD back to "none" (TwoFactorReset). Self-service and
    # administrator paths share this one action; the policy + operation tell them apart.
    post 'reset_two_factor', on: :member
    post 'magic_link', on: :collection
    post 'whatsapp_webhook', on: :collection
    get 'welcome', on: :collection
    get 'set_persona', on: :collection
    post 'reset_password', on: :collection
    post 'accept_terms', on: :collection
    get 'chat', on: :collection
    post 'chat', on: :collection
    get 'cross_site_link', on: :member
    # Change an existing mobile number, confirmed by a code emailed to the user:
    # create sends the code, show asks for it, update checks it (Users::PhoneChangesController).
    resource :phone_change, only: %i[show create update], module: :users

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
    get  :enroll_sms            # sms mode: confirm number + send test code
    post :verify_sms_enrollment # sms mode: verify test code
    # Costs real money per call. Rate limited in three places: a session cooldown here,
    # durable per-number/per-user limits in TwilioSmsDelivery, and a per-IP Rack::Attack
    # throttle — see docs/modules/two_factor_auth/twilio_sms_otp_design.md section 9.
    post :send_sms
  end

  post "/internal/sync/users",         to: "users_sync#upsert"
  post "/internal/sync/users/disable", to: "users_sync#disable"
  post "/internal/sync/users/digest",  to: "users_sync#digest" # optional reconciliation

  post "/ses_notifications", to: "ses_notifications#create"
  post "/grafana/alert", to: "grafana_alerts#alert"

  # The WhatsApp alert template's button is a Meta URL button: its base is fixed at
  # template-approval time (https://app.caphive.com/) and the send may only append a
  # suffix, so an alert cannot link straight at Grafana — passing the hostname produced
  # https://app.caphive.com/graphana.caphive.com. This hop is what the suffix points at
  # instead. Region is in the path because both regions' alerts render through the one
  # approved template, so US alerts arrive at the IN base and still have to reach
  # graphana.caphive.us. No conflict with /grafana/alert above: that is a POST, and the
  # constraint admits only "in" and "us", keeping this a fixed redirect rather than an
  # open one.
  # 302, not the redirect helper's default 301: a permanent redirect would be cached by
  # the browser and outlive any change to the Grafana hostnames.
  get "/grafana/:region",
      to: redirect(status: 302) { |params, _req|
        params[:region] == "us" ? "https://graphana.caphive.us" : "https://graphana.caphive.com"
      },
      constraints: { region: /in|us/ }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "entities#dashboard"

  resources :user_guides, only: [:index]
  get 'user_guides/*id', to: 'user_guides#show', as: :user_guide, format: false

  # Login-less help pages. Only the ids in PublicGuidesController::PUBLIC_GUIDE_IDS resolve;
  # the two-factor screens link here because the visitor is signed out at that point.
  # The path segment is the guide id so relative links between guides work under /help too.
  # Globbed like the /user_guides route: a plain :id segment rejects dots, which would turn
  # a "...user_guide.md" link into a routing error instead of a handled redirect.
  get 'help/*id', to: 'public_guides#show', as: :public_guide, format: false
  resources :release_notes, only: %i[index show], constraints: { id: %r{[^/]+} }

  # Internal documentation browser — CapHive staff only, see InternalDocPolicy.
  # /internal_docs, not /internal/docs: the /internal/* prefix above is already
  # taken by the machine-to-machine sync endpoints, and colliding there would be
  # confusing. Globbed *id with format: false for the same reason as the
  # user_guides route above: a plain :id segment rejects dots, which would break
  # ids containing them.
  resources :internal_docs, only: [:index]
  get 'internal_docs/*id', to: 'internal_docs#show', as: :internal_doc, format: false

  # Demo requests from the public website.
  #
  # POST is PUBLIC and cross-origin — caphive.com / caphive.us are static sites
  # with no writable endpoint of their own, so the form posts here on the app
  # host. GET (index/show) is CapHive staff only, via WebsiteLeadPolicy. Both
  # live on one controller, whose filter skips are scoped per action.
  #
  # The path is the one baked into the website's site_config partial, so it is
  # effectively public API: changing it means rebuilding and redeploying the
  # static site in lockstep. The Rack::Attack throttle keys on it literally
  # (config/initializers/rack_attack.rb, 'website_leads/ip').
  #
  # The OPTIONS route is preflight insurance. Today's client sends only
  # CORS-safelisted headers so no preflight fires; adding one later would
  # otherwise break submission with a failure invisible in our logs.
  resources :website_leads, only: %i[index show create]
  match 'website_leads', to: 'website_leads#options', via: :options

  # /features is retired. The documents still linked through it — the US GTM
  # strategy (us_gtm.md) and its feature specs (us_gtm/) — now live in docs/gtm/,
  # the internal docs viewer's section, so ids are forwarded there. The rest of
  # the old docs/features/ specs (now under docs/modules/) are not browsable;
  # those ids land on the viewer's "not found" redirect. Kept as 302 redirects —
  # not 301 — so existing links and bookmarks keep working without being cached
  # permanently in browsers.
  # Unnamed on purpose: nothing in the app links here any more, so a
  # features_path helper would only invite new callers to the retired URL.
  get 'features', to: redirect(status: 302) { '/internal_docs' }
  get 'features/*id',
      to: redirect(status: 302) { |params, _req|
        # params[:id] arrives percent-DECODED, and Redirect#serve runs URI.parse
        # on whatever this block returns. An id carrying a space or any other
        # non-URI byte ("/features/foo%20bar") would raise URI::InvalidURIError
        # inside the router, where the controllers' rescue_from never sees it —
        # a 500 and an exception alert rather than the clean 302 the retired
        # FeaturesController gave. So re-escape, per segment, to keep the "/"
        # separators. Dropping empty segments also stops a leading slash from
        # turning this into a protocol-relative "//host" redirect.
        segments = params[:id].to_s.split("/").reject(&:empty?).map { |s| ERB::Util.url_encode(s) }
        "/internal_docs/gtm/#{segments.join('/')}"
      },
      format: false

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
