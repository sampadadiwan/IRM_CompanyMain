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
