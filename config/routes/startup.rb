resources :investor_kpi_mappings do
  post 'generate', on: :collection
  patch 'recompute_rag', on: :member
end

resources :kpis do
  patch 'approve', on: :member
  patch 'unapprove', on: :member
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
  patch "mark_reviewed", on: :member
  post "validate_upload", on: :member      # dry-run workbook validation for the pre-save panel (saved report)
  post "validate_upload", on: :collection  # same, for the New page (report context from form fields)
  patch "reopen", on: :member              # fund: reopen a submitted report and ask the portco to re-upload
  get "template", on: :member              # pre-filled KPI workbook template (portco + fund)
  get "template", on: :collection          # same, for the New page (report context from form fields)
  get "portco_pending", on: :collection
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
  patch 'bulk_update_status', on: :collection
  patch 'bulk_advance_activity', on: :collection
end
resources :deals do
  get 'search', on: :collection
  get 'overview', on: :member
  get 'investor_deals', on: :collection
  get 'consolidated_access_rights', on: :member
  get 'analytics', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
  get :agent_settings, on: :member
  patch :agent_settings, action: :update_agent_settings, on: :member
  post :run_now, on: :member
  get :weekly_summary, on: :member
  patch :update_ingest_address, on: :member

  # Warehouse items — emails the Deal Update Agent couldn't auto-file.
  # Nested under deals because items are always deal-scoped.
  # @see WarehouseItemsController
  resources :warehouse_items, only: [:index], controller: "warehouse_items" do
    patch :resolve, on: :member
  end
end
