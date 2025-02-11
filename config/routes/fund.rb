resources :portfolio_cashflows
resources :stock_adjustments
resources :stock_conversions do
  post :reverse, on: :member
end

resources :scenario_investments
resources :ci_track_records
resources :ci_widgets

resources :portfolio_scenarios do
  patch 'run', on: :member
  get 'simple_scenario', on: :collection
  post 'simple_scenario', on: :collection
end

resources :fund_reports do
  patch "regenerate", on: :member
  patch "download_page", on: :member
end
resources :commitment_adjustments

resources :investor_advisors do
  post 'switch', on: :collection
end

resources :aggregate_portfolio_investments do
  patch 'toggle_show_portfolio', on: :member
end

resources :fund_formulas do
  patch "enable_formulas", on: :collection
end

resources :fund_unit_settings
resources :portfolio_investments do
  get 'base_amount_form', on: :collection
end

resources :investment_instruments do
  get 'sub_categories', on: :collection
end

resources :account_entries do
  post 'delete_all', on: :collection
  get 'adhoc', on: :collection
  post 'adhoc', on: :collection
end

resources :fund_units
resources :fund_ratios
resources :capital_remittance_payments

resources :capital_distribution_payments do
  get 'search', on: :collection
end
resources :capital_distributions do
  post 'approve', on: :member
  patch 'redeem_units', on: :member
  patch 'payments_completed', on: :member
end
resources :capital_remittances do
  patch 'verify', on: :member
  get 'search', on: :collection
  patch 'generate_docs', on: :member
  patch 'send_notification', on: :member
  post 'bulk_actions', on: :collection
end
resources :capital_calls do
  get 'search', on: :collection
  post 'reminder', on: :member
  post 'approve', on: :member
  patch 'generate_docs', on: :member
  patch 'allocate_units', on: :member
  patch 'recompute_fees', on: :member
end

resources :capital_commitments do
  patch 'generate_documentation', on: :member
  patch 'generate_soa', on: :member
  get 'generate_soa_form', on: :member
  patch 'generate_esign_link', on: :member
  get 'search', on: :collection
  get 'report', on: :member
  get 'documents', on: :collection
  get 'transfer_fund_units', on: :member
  post 'transfer_fund_units', on: :member
end

resources :funds do
  get 'last', on: :member
  get 'report', on: :member
  post 'generate_fund_ratios', on: :member
  get 'generate_fund_ratios', on: :member
  patch 'allocate', on: :member
  patch 'generate_documentation', on: :member
  get 'allocate_form', on: :member
  get 'copy_formulas', on: :member
  get 'export', on: :member
  get 'check_access_rights', on: :member
  delete 'delete_all', on: :member
  get 'generate_reports', on: :member
  post 'generate_reports', on: :member
  get 'dashboard', on: :member
  post 'generate_tracking_numbers', on: :member
end

resources :expression_of_interests do
  patch 'approve', on: :member
  patch 'allocate', on: :member
  get   'allocation_form', on: :member
  get 'search', on: :collection
  patch 'generate_documentation', on: :member
  patch 'generate_esign_link', on: :member
end

resources :investment_opportunities do
  patch 'toggle', on: :member
  post 'allocate', on: :member
  get 'search', on: :collection
  patch 'send_notification', on: :member
  get 'finalize_allocation', on: :member
  get 'no_password_show', on: :collection
end

resources :allocation_runs do
  patch 'lock', on: :member
  patch 'unlock', on: :member
end
