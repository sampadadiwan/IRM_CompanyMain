resources :faq_threads do
  post :create_message, on: :member
end
resources :support_agents do
  post 'run', on: :collection
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
    end
  end

  resources :ai_chat_messages, only: [:create]
end

resources :assistants, only: [:show] do
  post :ask, on: :collection
  post :transcribe, on: :collection
end
