resources :investor_kpi_mappings do
  post 'generate', on: :collection
end

resources :kpis do
  patch 'approve', on: :member
  delete 'reject', on: :member
  patch 'approve_all', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :kpi_reports do
  patch 'recompute_cumulative', on: :member
  patch 'recompute_percentage_change', on: :member
  post "analyze", on: :member
  post 'send_portco_notification', on: :collection
  post 'chart_refresh', on: :collection
  post 'trigger_periodic_reports', on: :collection
  post 'trigger_periodic_reports', on: :member
  get "show_performance", on: :collection
  get "new_notification", on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
  patch "refresh_import", on: :member
end

resources :kpi_chart_settings, only: %i[index create destroy show]
resources :share_transfers

resources :valuations do
  get 'analytics', on: :collection
  post 'value_bridge', on: :collection
  get 'value_bridge', on: :collection
end

resources :deal_activities do
  get 'search', on: :collection
  get 'update_sequence', on: :member
  post 'update_sequences', on: :collection
  post 'toggle_completed', on: :member
  post 'perform_activity_action', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
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
  get 'analytics', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
