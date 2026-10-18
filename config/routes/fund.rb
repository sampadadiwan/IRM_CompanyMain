resources :investments
resources :portfolio_cashflows
resources :stock_adjustments
resources :stock_conversions do
  post :reverse, on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :scenario_investments
resources :ci_track_records
resources :ci_widgets

resources :portfolio_scenarios do
  patch 'run', on: :member
  get 'simple_scenario', on: :collection
  post 'simple_scenario', on: :collection
  post 'finalize', on: :member
end

# Fund financial statements from account entries — see openspec/changes/fund-financial-statements
resources :financial_statements, only: %i[index show create] do
  post 'setup', on: :collection
  post 'regenerate', on: :member
  patch 'lock', on: :member
end
resources :financial_statement_mappings, only: %i[index] do
  # Statements preview, opened in its own browser tab from the Mapping tab
  get 'preview', on: :collection
end
resources :financial_statement_accounts, only: %i[new create edit update destroy]
resources :financial_statement_mapping_rules, only: %i[new create edit update destroy]
resources :financial_statement_definitions, only: %i[index new create edit update destroy]
resources :financial_statement_layout_rows, only: %i[new create edit update destroy] do
  post 'sort', on: :collection
end
resources :financial_statement_settings, only: %i[edit update]
resources :financial_statement_mapping_suggestions, only: %i[new create show] do
  patch 'approve', on: :member
  patch 'discard', on: :member
  patch 'retry_draft', on: :member
  patch 'move', on: :member
  patch 'flip', on: :member
end

resources :fund_reports do
  patch "regenerate", on: :member
  patch "download_page", on: :member
end
resources :commitment_adjustments

resources :investor_advisors do
  post 'switch', on: :collection
  get 'new_for_investor', on: :collection
  post 'create_for_investor', on: :collection
end

# LP Company Dashboard — one page per portfolio company for LPs, and the fund team's preview (lp-folio-portfolio-dashboard)
get 'lp/portfolio_companies/:id', to: 'lp_company_dashboards#show', as: :lp_company_dashboard
get 'lp/portfolio_companies/:id/preview', to: 'lp_company_dashboards#preview', as: :preview_lp_company_dashboard

resources :aggregate_portfolio_investments do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :aggregate_portfolio_investment_snapshots, controller: "aggregate_portfolio_investments", defaults: { snapshot: true }

resources :fund_formulas do
  patch "enable_formulas", on: :collection
  get "generate_ai_descriptions", on: :collection
  get "generate_ai_description", on: :member
  get "generate_formula", on: :collection
  get "dependencies", on: :collection
  post 'bulk_actions', on: :collection
  post 'fetch_templates', on: :collection
end

# Actions > Incremental allocation / Suggest run checks on the fund formulas page (support only)
resources :fund_formula_operations, only: %i[index show create] do
  get "suggestions", on: :collection
  patch "apply", on: :member
  post "add_suggestions", on: :member
  post "download_suggestions", on: :member
end

resources :fund_unit_settings
resources :portfolio_investments do
  get 'base_amount_form', on: :collection
  post 'check_duplicate_sell', on: :collection
end
resources :portfolio_investment_snapshots, controller: "portfolio_investments", defaults: { snapshot: true }

resources :investment_instruments do
  get 'sub_categories', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :account_entries do
  post 'delete_all', on: :collection
  get 'adhoc', on: :collection
  post 'adhoc', on: :collection
  post 'explain', on: :member
  # One opened line of the entry page's explanation, fetched into its Turbo Frame.
  get 'explanation_node', on: :member
end

resources :account_entry_reports, only: [] do
  get 'fund_report', on: :collection
  get 'folio_report', on: :collection
  post 'generate_commentary', on: :collection
  # What each of a run's entry-name totals is built from — see
  # docs/modules/allocation/allocation_run_review_proposals.md (proposal 1).
  get 'dependencies', on: :collection
  # The tie-out sheet (proposal 3 in docs/modules/allocation/allocation_run_review_proposals.md)
  # is hidden for now. Its code is kept, but it has no routes, so it cannot be reached by URL
  # either. To bring it back, restore:
  #   get 'tie_out', on: :collection
  #   get 'tie_out_folios', on: :collection
  # and, below, `resources :tie_out_figures, only: :create`.
end

resources :fund_units do
  post 'bulk_actions', on: :collection
end

resources :fund_ratios do
  post 'bulk_actions', on: :collection
end

resources :fund_ratio_runs, only: %i[index show]

resources :fund_ratio_run_templates do
  post 'trigger_all',    on: :collection
  post 'trigger_by_tag', on: :collection
  post 'trigger_one',    on: :member
  get  'runs',           on: :member
end

# Allocation run templates and groups — see docs/modules/allocation/allocation_run_templates.md
resources :allocation_run_templates do
  # JSON: statement documents available on a fund, for the template form's fund switch
  get 'statement_documents', on: :collection
end
resources :allocation_run_template_groups, except: :index do
  get  'preflight', on: :member # the up-front check page, before anything runs
  post 'run',       on: :member # records the group run and enqueues the job
end
resources :allocation_group_runs, only: %i[index show]

resources :capital_remittance_payments do
  get "preview", on: :member
end

resources :capital_distribution_payments do
  get 'search', on: :collection
  get "preview", on: :member
  patch 'generate_docs', on: :member
  patch 'payments_completed', on: :member
  patch 'send_notification', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :capital_distributions do
  post 'approve', on: :member
  # P12 (phase 10): approve / redeem units for many distributions in one request
  post 'bulk_actions', on: :collection
  # The journey panel alone, for real-time refreshes (capital-distribution-journey E16, E17)
  get 'journey', on: :member
  patch 'redeem_units', on: :member
  patch 'payments_completed', on: :member
  get 'add_pis_to_capital_distribution', on: :collection
  patch 'generate_docs', on: :member
  patch 'send_payment_notifications', on: :member
  patch 'recompute_fees', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :capital_remittances do
  patch 'verify', on: :member
  get 'search', on: :collection
  patch 'generate_docs', on: :member
  patch 'send_notification', on: :member
  post 'bulk_actions', on: :collection
  get 'bulk_verify_modal', on: :collection
  get "preview", on: :member
  post 'allocate_units', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :capital_calls do
  # P12 (phase 10): approve / allocate units for many calls in one request
  post 'bulk_actions', on: :collection
  get 'search', on: :collection
  post 'reminder', on: :member
  post 'approve', on: :member
  patch 'unapprove', on: :member
  post 'notify', on: :member
  patch 'generate_docs', on: :member
  patch 'allocate_units', on: :member
  patch 'recompute_fees', on: :member
  get 'journey', on: :member # journey panel only, reloaded in place by real-time updates
  get 'stats', on: :member # stats cards only, reloaded in place once CapitalRemittancesCountersJob fixes the totals
  post 'confirm_reconciliation_deposit', on: :member
  post 'reassign_reconciliation_deposit', on: :member
  post 'undo_reconciliation_deposit', on: :member
  post 'confirm_all_exact_reconciliation_deposits', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

# Side letter obligation tracking (LP Obligation Matrix + review gate)
resources :side_letters
resources :side_letter_obligations do
  member do
    patch :approve
    patch :reject
    patch :waive
    patch :revert
    post :fire
    post :fulfill
  end
end

resources :capital_commitments do
  # funds-json-api-hardening ⑦: one folio's calls, payments, distributions and ledger totals (H9)
  get 'statement', on: :member
  patch 'generate_documentation', on: :member
  patch 'generate_soa', on: :member
  get 'generate_soa_form', on: :member
  patch 'generate_esign_link', on: :member
  get 'search', on: :collection
  get 'report', on: :member
  get 'documents', on: :collection
  get 'transfer_fund_units', on: :member
  post 'transfer_fund_units', on: :member
  put :restore_deleted, on: :member
  get 'performance_chart', on: :member
  get :show_deleted, on: :collection
  get 'preview', on: :member
end

resources :funds do
  resources :ratio_formulas
  # funds-json-api-hardening ⑦: the fund overview's figures as JSON (H8)
  get 'summary', on: :member
  # P6: recompute the call / fund / commitment collected totals from the remittances (H27)
  patch 'recompute_totals', on: :member
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
  get 'dashboard', on: :member
  get 'analytics', on: :member
  post 'generate_tracking_numbers', on: :member
  get 'change_tracking_currency', on: :member
  post 'change_tracking_currency', on: :member
  post 'retry_tracking_currency_change', on: :member
  get 'show_email_list', on: :member
  patch 'trigger_adhoc_notification', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :fund_snapshots, controller: "funds", defaults: { snapshot: true }

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
  get 'show_email_list', on: :member
  patch 'trigger_adhoc_notification', on: :member
end

resources :allocation_runs do
  patch 'lock', on: :member
  patch 'unlock', on: :member
  patch 'unlock_all', on: :collection
end

# Allocation run checker — see docs/modules/allocation/allocation_run_checker_requirements.md.
# create takes an allocation_run_id and queues the checks; show renders the report.
resources :allocation_run_reports, only: %i[show create]

# A typical setup's values (JSON) for the evergreen wizard — also used before the fund exists
get "evergreen_presets/:name", to: "evergreen/presets#show", as: :evergreen_preset

# Evergreen (open-ended) funds — every evergreen screen lives under the fund.
# Worked examples H1–H39 — openspec/changes/open-ended-funds/design.md#worked-examples
scope "funds/:fund_id/evergreen", module: :evergreen, as: :evergreen do
  # Copy investor-email templates from another evergreen fund (§ Notifications)
  resource :notification_copy, only: %i[new create]
  # A fund's type is chosen on New Fund and can't be changed: no create (make evergreen) or destroy
  # (switch back) here (evergreen-fund-on-create ⑤)
  resource :settings, only: %i[show update]
  resource :overview, only: :show, controller: :overview
  resources :navs, only: %i[index show create destroy] do
    post :import, on: :collection
    member do
      patch :override
      patch :approve
      patch :reopen
      patch :recalculate
      # Include / exclude a late management fee on a draft (evergreen-late-management-fees ⑤)
      patch :decide_late_fee
    end
  end
  resources :orders, only: %i[index show new create] do
    post :preview, on: :collection
    post :import, on: :collection
    member do
      patch :cancel
      patch :accept
      patch :reject
      patch :verify_signatory
      post :upload_form
      post :record_payment
      post :accept_received
    end
  end
  resources :dealing_dates, only: %i[index show], path: "dealing" do
    member do
      post :confirm
      post :undo
      post :close
      post :generate_documents
      post :approve_documents
    end
    resources :fills, only: [], controller: :dealing_fills do
      member do
        post :record_payment
        post :verify
        post :mark_paid
        post :resend
        post :regenerate
      end
    end
  end
  resources :investors, only: :index
  resource :fees, only: :show do
    post :seed_formula
  end
  resources :settlements, only: :show
  # Link an approved KYC to a folio that has none (evergreen-folio-soa ③)
  resources :folios, only: :show do
    patch :link_kyc, on: :member
  end
  # Generate statements for one folio or every folio of the fund (evergreen-folio-soa ④)
  resources :statements, only: :create
end

# Journey panel frames for evergreen records (real-time refresh convention: /<plural>/:id/journey)
resources :dealing_orders, only: [] do
  get :journey, on: :member
end
resources :dealing_dates, only: [] do
  get :journey, on: :member
end
