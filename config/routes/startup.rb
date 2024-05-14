resources :investor_kpi_mappings do
  post 'generate', on: :collection
end

resources :kpis
resources :kpi_reports do
  patch 'recompute_percentage_change', on: :member
end

resources :share_transfers
resources :investment_snapshots

resources :valuations
resources :excercises do
  patch 'approve', on: :member
  get 'search', on: :collection
end

resources :vestings
resources :option_pools do
  patch 'approve', on: :member
  patch 'run_vesting', on: :member
end

resources :aggregate_investments do
  get 'investor_investments', on: :collection
  get 'simple_simulator', on: :collection
  get 'new_simulator', on: :collection
end

resources :funding_rounds

resources :holdings do
  get 'search', on: :collection
  post 'employee_calc', on: :collection
  post 'employee_calc_excercise_form', on: :collection
  post 'investor_calc', on: :collection
  patch 'cancel', on: :member
  patch 'approve', on: :member
  patch 'emp_ack', on: :member
  post 'approve_all_holdings', on: :collection
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
  get 'investor_deals', on: :collection
  get 'kanban', on: :member
end

resources :investments do
  get 'search', on: :collection
  get 'history', on: :member
  get 'investor_investments', on: :collection
  post 'recompute_percentage', on: :collection
end
