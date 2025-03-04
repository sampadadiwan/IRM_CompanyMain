resources :investor_kpi_mappings do
  post 'generate', on: :collection
end

resources :kpis
resources :kpi_reports do
  patch 'recompute_percentage_change', on: :member
end

resources :share_transfers

resources :valuations do
  post 'value_bridge', on: :collection
  get 'value_bridge', on: :collection
end

resources :deal_activities do
  get 'search', on: :collection
  get 'update_sequence', on: :member
  post 'update_sequences', on: :collection
  post 'toggle_completed', on: :member
  post 'perform_activity_action', on: :member
end
resources :deal_investors do
  get 'search', on: :collection
  get 'kanban_search', on: :collection
end
resources :deals do
  get 'search', on: :collection
  get 'overview', on: :member
  get 'investor_deals', on: :collection
  get 'consolidated_access_rights', on: :member
end
