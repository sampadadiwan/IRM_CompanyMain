resources :portfolio_cashflows
resources :stock_adjustments
resources :scenario_investments

resources :portfolio_scenarios do
  patch 'run', on: :member
  get 'simple_scenario', on: :collection
  post 'simple_scenario', on: :collection
end

resources :fund_reports
resources :commitment_adjustments

resources :investor_advisors do
  post 'switch', on: :collection
end

resources :aggregate_portfolio_investments

resources :fund_formulas
resources :fund_unit_settings
resources :portfolio_investments do
  get 'sub_categories', on: :collection
end

resources :account_entries
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
end
resources :capital_calls do
  get 'search', on: :collection
  post 'reminder', on: :member
  post 'approve', on: :member
  patch 'generate_docs', on: :member
  patch 'allocate_units', on: :member
end

resources :capital_commitments do
  patch 'generate_documentation', on: :member
  patch 'generate_soa', on: :member
  get 'generate_soa_form', on: :member
  patch 'generate_esign_link', on: :member
  get 'search', on: :collection
  get 'report', on: :member
  get 'documents', on: :collection
end

resources :funds do
  get   'timeline', on: :member
  get   'last', on: :member
  get 'report', on: :member
  get 'generate_fund_ratios', on: :member
  patch 'allocate', on: :member
  patch 'generate_documentation', on: :member
  get 'allocate_form', on: :member
  get 'copy_formulas', on: :member
  get 'export', on: :member
  get 'check_access_rights', on: :member
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
end
