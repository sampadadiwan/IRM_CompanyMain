resources :faq_threads do
  post :create_message, on: :member
end

resources :support_agents do
  collection do
    post  'run'
    post  'setup'
    get   'llm_keys'
    patch 'llm_keys', action: 'update_llm_keys'
    get   'note_summaries'
    patch 'update_score'
    patch 'update_note_summary'
    get   'deal_steps'
  end
  member do
    post 'run_with_steps'
    post 'run_batch'
    post 'cancel'
    get 'status'
    get 'step_details'
    get 'deal_steps'
  end

  # Agent Schedule routes
  resource :agent_schedule, only: %i[show create update destroy] do
    get :executions, on: :collection
    get 'executions/:execution_id', action: :execution, as: :execution, on: :collection
  end

  # Generic chat routes
  resources :chats, controller: 'support_agent_chats', only: %i[index create destroy] do
    collection do
      get :sessions
    end
    member do
      patch :feedback, controller: 'support_agent_chat_feedbacks', action: :update
    end
  end
end

# CS Feedback Review Dashboard — Super Admin queue for flagged responses + escalations
resources :cs_feedback_reviews, only: %i[index show update] do
  member do
    post :retest
  end
end

resources :customer_support_escalations, only: %i[show update]

# FAQ Manager — support-managed user-guide FAQs and chatbot guide search (docs/ai/guide_faq_search_prd.md)
resources :faq_entries do
  member do
    patch :publish
    patch :archive
    patch :verify
  end
  collection do
    post :import
  end
end
resources :guide_search_synonyms, except: %i[show]
resources :guide_search_misses, only: %i[index]
# All FAQs from every user guide on one page, for anyone who can read the guides
get 'faqs', to: 'faqs#index', as: :faqs

resources :agent_charts do
  post 'regenerate', on: :member
end
resource :portfolio_company_dashboard, only: [:show], controller: "portfolio_company_dashboard" do
  post :send_reminders
  post :run_validation
end

# Portfolio Scoring Dashboard — buckets portfolio companies by grade tier
resource :portfolio_scoring_dashboard, only: [:show], controller: "portfolio_scoring_dashboard" do
  post :run_scoring
end

# Presentation Analyst Dashboard — buckets portfolio companies by Management
# Accountability tier, aggregates cross-period flags and the pre-board
# briefing across the portfolio.
resource :presentation_analyst_dashboard, only: [:show], controller: "presentation_analyst_dashboard" do
  post :run_analysis
end

resources :ai_checks do
  post 'run_checks', on: :collection
  get 'run_checks', on: :collection
end
resources :chats do
  post :send_message, on: :member
end
resources :ai_rules

# AI Portfolio Report Builder
resources :ai_portfolio_reports do
  collection do
    post :create_from_folder
    get  :evaluation_folder_documents
    post :upload_evaluation_documents
  end

  member do
    get :collated_report           # View the collated report page
    patch :save_collated_report    # Save edits to collated report
    get :export_pdf                # Export as PDF
    get :export_docx               # Export as Word
    patch :toggle_master_web_search
  end

  resources :ai_report_sections do
    member do
      post :add_content
      post :regenerate
      patch :toggle_web_search
      post :toggle_reviewed
      post :generate_chart_preview
      post :insert_chart
      post :remove_chart
    end
  end
end

resources :investment_criteria_templates do
  member do
    get :preview # For AJAX preview in report creation form
  end
end

resources :assistants, only: [:show] do
  collection do
    post :ask
    post :transcribe
    get :generate_slides
    get :efficiency_report
  end
end

resources :assistant_tasks

post    '/mcp', to: 'mcp#create'
get     '/mcp', to: 'mcp#create'    # SSE endpoint for server-initiated messages (MCP Streamable HTTP)
options '/mcp', to: 'mcp#preflight' # CORS preflight
