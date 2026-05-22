resources :faq_threads do
  post :create_message, on: :member
end

resources :support_agents do
  collection do
    post  'run'
    get   'note_summaries'
    patch 'update_score'
    patch 'update_note_summary'
  end
  member do
    post 'run_with_steps'
    post 'run_batch'
    post 'cancel'
    get 'status'
    get 'step_details'
  end

  # Agent Schedule routes
  resource :agent_schedule, only: %i[show create update destroy] do
    get :executions, on: :collection
    get 'executions/:execution_id', action: :execution, as: :execution, on: :collection
  end

  # Generic chat routes
  resources :chats, controller: 'support_agent_chats', only: %i[index create destroy]
end

resources :agent_charts do
  post 'regenerate', on: :member
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
