resources :validation_rules, only: %i[index new create edit update destroy] do
  post :evaluate, on: :collection
end

# Workflow templates (company_admin only for mutations; all employees read-only)
resources :workflow_templates do
  # Seeds a kind's standard journeys, params[:kind] in JourneySetup::KINDS (same service as the
  # rollout rake tasks). Worked examples H10 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  post :setup_journeys, on: :collection
  # Retire a template (or bring it back) without deleting it — see WorkflowTemplate.enabled
  patch :toggle_enabled, on: :member
  # Copy a template with its steps (investor-kyc-journey E26)
  post :duplicate, on: :member
  resources :workflow_steps, except: %i[index show]
  # Auto-assignment rules are nested under their template
  resources :workflow_auto_assignment_rules, except: %i[show]
end

# Company-admin-facing UI: view all rules + manage their entity's overrides
resources :validation_rule_overrides, only: %i[index new create edit update destroy]

resources :quick_link_steps
resources :quick_links do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :custom_notifications do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :reports do
  post 'prompt', on: :collection
  get 'dynamic', on: :member
  post 'generate_report_insight', on: :member
end

scope path: 'report_builder', controller: :report_builder do
  get    'new',                      action: :new,               as: :new_report_builder
  get    'models',                   action: :models,            as: :report_builder_models
  get    'associations',             action: :associations,      as: :report_builder_associations
  post   '',                         action: :create,            as: :report_builder_create
  # Guided wizard — a friendlier, step-by-step on-ramp that sits in front of
  # the existing builder (below). It creates/mutates the same Report via the
  # same actions as the advanced builder, so there is exactly one place that
  # understands the report_builder template format.
  get    'wizard',                   action: :wizard_new,        as: :wizard_report_builder
  post   'wizard',                   action: :wizard_create,     as: :wizard_report_builder_create
  # Starting points: the template page, creating from a template, Duplicate
  # (report-builder-starting-points)
  get    'templates',                action: :templates,         as: :report_builder_templates
  post   'templates/:key',           action: :create_from_template, as: :create_report_builder_from_template
  post   ':id/duplicate',            action: :duplicate,         as: :duplicate_report_builder
  # Describe it — the AI assistant's drafts (report-builder-assistant)
  get    'describe',                 action: :describe,          as: :report_builder_describe
  post   'describe',                 action: :describe_create,   as: :report_builder_describe_create
  get    ':id/draft',                action: :draft,             as: :report_builder_draft
  get    ':id/draft/state',          action: :draft_state,       as: :report_builder_draft_state
  post   ':id/draft/refine',         action: :draft_refine,      as: :report_builder_draft_refine
  post   ':id/draft/fund',           action: :draft_fund,        as: :report_builder_draft_fund
  patch  ':id/draft/chart',          action: :draft_chart,       as: :report_builder_draft_chart
  post   ':id/draft/chart',          action: :draft_describe_chart, as: :report_builder_draft_describe_chart
  patch  ':id/draft/save',           action: :draft_save,        as: :report_builder_draft_save
  delete ':id/draft',                action: :draft_discard,     as: :report_builder_draft_discard
  get    ':id/wizard/:step',         action: :wizard_step,       as: :wizard_report_builder_step
  post   ':id/wizard_filter',        action: :wizard_add_filter,    as: :wizard_report_builder_add_filter
  delete ':id/wizard_filter',        action: :wizard_remove_filter, as: :wizard_report_builder_remove_filter
  get    ':id/edit',                 action: :edit,              as: :edit_report_builder
  get    ':id/preview',              action: :preview,           as: :preview_report_builder
  get    ':id/view',                 action: :view,              as: :view_report_builder
  get    ':id/download',             action: :download,          as: :download_report_builder
  patch  ':id/template',             action: :update_template,   as: :update_report_builder_template
  post   ':id/columns',              action: :add_column,        as: :add_report_builder_column
  delete ':id/columns/:gvp_id',      action: :remove_column,     as: :remove_report_builder_column
  patch  ':id/columns/:gvp_id',      action: :update_column_label, as: :update_report_builder_column_label
  patch  ':id/columns/:gvp_id/move', action: :move_column,       as: :move_report_builder_column
  post   ':id/undo',                  action: :undo,              as: :undo_report_builder
  get    ':id/filter_row',            action: :filter_row,        as: :report_builder_filter_row
  get    ':id/pivot_preview',         action: :pivot_preview,     as: :report_builder_pivot_preview
  post   ':id/join',                 action: :add_join,          as: :add_report_builder_join
  delete ':id/join',                 action: :remove_join,       as: :remove_report_builder_join
  patch  ':id/aggregate',            action: :update_aggregate,  as: :update_report_builder_aggregate
  patch  ':id/sort',                 action: :update_sort,       as: :update_report_builder_sort
  patch  ':id/name',                 action: :update_name,       as: :update_report_builder_name
  patch  ':id/pivot',                action: :update_pivot,      as: :update_report_builder_pivot
  patch  ':id/join_settings',        action: :update_join_settings, as: :update_report_builder_join_settings
  patch  ':id/schedule',             action: :update_schedule,      as: :update_report_builder_schedule
  post   ':id/schedule_check',       action: :schedule_check,       as: :report_builder_schedule_check
  post   ':id/schedule_test',        action: :schedule_test,        as: :report_builder_schedule_test
  post   ':id/formulas',             action: :add_formula,       as: :add_report_builder_formula
  delete ':id/formulas/:key',        action: :remove_formula,    as: :remove_report_builder_formula
  post   ':id/validate_formula',     action: :validate_formula,  as: :validate_report_builder_formula
end

resources :report_insights
resources :audits
resources :email_bounce_events, only: [:index] do
  post :disable_recipient_email, on: :member
end
resources :reminders do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :favorites do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :permissions

resources :task_templates do
  post 'generate', on: :collection
end

resources :tasks do
  get 'search', on: :collection
  get 'deal_tasks', on: :collection
  patch 'completed', on: :member
  # Kanban board drag & drop target (tasks/_board.html.erb)
  patch 'update_status', on: :member
  delete 'destroy_series', on: :member
end

resources :form_custom_fields do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

# The custom fields side panel on record pages (openspec/changes/grid-columns-inline-settings — phase 4, D14)
resources :form_type_fields, only: [] do
  collection do
    get :settings
    patch :save
  end
end

resources :form_types do
  # M25 — cloning writes a copy into the user's firm, so it is a POST (a GET link or prefetch must not
  # create anything); GET now gives 404 (M25-1)
  post 'clone', on: :member
  patch 'rename_fcf', on: :member
  patch 'add_regulatory_fields', on: :member
  get 'generate_upload_xlsx', on: :member
  get 'edit_step_labels', on: :member
  patch 'update_step_labels', on: :member
end

resources :e_signatures do
  # Embedded signing: the signing page and the result the page reports (openspec/changes/embedded-esign-digio)
  get 'sign', on: :member
  post 'sign_result', on: :member
end
resources :stamp_papers
resources :investor_notice_items
resources :exchange_rates do
  post 'generate_tracking_numbers', on: :member
end

# Entity Market Data settings and feed runs — openspec/changes/fund-market-data (card ①, ②)
namespace :market_data do
  resource :settings, only: %i[show update] do
    # GET too: a browser reload of the results page re-runs the dry run (it stores nothing, E45)
    match :test_feed, via: %i[get post]
  end
  resources :runs, only: %i[index]
end
# Derivatives — fund-market-data, card ⑥
resources :funds, only: [] do
  resources :derivative_contracts, only: %i[index new create], shallow: true
end
resources :derivative_contracts, only: %i[show edit update] do
  post :record_event, on: :member
end
resources :corporate_action_suggestions, only: %i[index] do
  patch :confirm, on: :member
  patch :dismiss, on: :member
end

resources :approval_responses do
  patch 'approve', on: :member
  # GET shows the confirm card for an emailed answer link; only the POST from that card saves it
  get 'email_response', on: :member
  post 'email_response', on: :member
  get 'preview', on: :member
end
resources :approvals do
  patch 'approve', on: :member
  patch 'send_reminder', on: :member
  patch 'close', on: :member
end

resources :individual_kycs, controller: "investor_kycs", type: "IndividualKyc"
resources :non_individual_kycs, controller: "investor_kycs", type: "NonIndividualKyc"
resources :investor_kycs do
  get 'analytics', on: :collection
  get 'journey', on: :member
  get 'preview', on: :member
  get 'search', on: :collection
  put 'toggle_verified', on: :member
  patch 'send_notification', on: :member
  post 'send_kyc_reminder', on: :member
  post 'notify_kyc_required', on: :member
  post 'send_kyc_reminder_to_all', on: :collection
  put 'generate_new_aml_report', on: :member
  put 'override_aml_status', on: :member
  post 'compare_kyc_datas', on: :collection
  put 'assign_kyc_data', on: :member
  get 'edit_my_kyc', on: :collection
  get 'generate_docs', on: :member # Just show the form
  patch 'generate_docs', on: :member # Actually generate the docs
  get 'generate_all_docs', on: :collection
  post 'generate_all_docs', on: :collection # Generate docs for entire fund or entity
  post 'bulk_actions', on: :collection
  post 'extract_docs_data', on: :member
  get  'processing', on: :member
  patch 'doc_first_upload', on: :member
  post 'create_and_send_kyc_to_investor', on: :collection
  get "download_kra_data", on: :member
  get "fetch_ckyc_data", on: :member
  get 'esign_emails', on: :collection
  get 'edit_reporting_fields', on: :member
  put 'update_reporting_fields', on: :member
  post 'request_updates', on: :member
  get  'investor_pending', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :aml_reports do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :kyc_datas do
  get 'search', on: :collection
  # No `fetch_ckyc_data` collection route: KycDatasController has no such action. CKYC data is fetched
  # through the investor_kycs member route of the same name (F5-4)
  get 'send_ckyc_otp', on: :member
  put 'download_ckyc_with_otp', on: :member
  put 'refresh', on: :member
  get 'compare_ckyc_kra', on: :collection
end

resources :payments do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :nudges do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
resources :import_uploads do
  delete 'delete_data', on: :member
end

# Dedicated new/create/validate_upload stack for ShareholderPosition bulk uploads only - mirrors
# how KPI reports have their own dedicated upload+validate flow (KpiReportsController), so the
# Fully Dilluted % pre-Save check never touches the generic ImportUploadsController or its
# shared new/edit/_xlsx_preview views used by every other bulk import type. Still persists via
# the same ImportUpload model (import_type: "ShareholderPosition") - see
# ShareholderPositionUploadsController.
resources :shareholder_position_uploads, only: %i[new create] do
  post 'validate_upload', on: :collection
end

resources :folders do
  get  'download',         on: :member
  post 'generate_report',  on: :member
  get  'generate_report',  on: :member
  get  'data_rooms',       on: :collection
  put  :restore_deleted,   on: :member
  get  :show_deleted,      on: :collection
  # Changed: Controller from "folder_nda_configs" to "nda_configs".
  # Why: NdaConfig is now polymorphic — controller moved to core/nda_configs pack.
  # Singular resource (not resources) because each owner has at most one NDA config.
  # No destroy action — NDA configs are disabled, not deleted (soft delete via Trackable).
  resource :nda_config, controller: "nda_configs", only: %i[new create edit update]
end

# Changed: Added NDA acceptance routes for Module 2 LP Acceptance Flow.
# Why: Standalone resource (not nested under folders) — NDA acceptance is tied to
#   NdaConfig (polymorphic), not to a specific owner type. folder_id passed as query param.
resources :nda_acceptances, controller: "nda_acceptances", only: %i[index create] do
  post :decline, on: :collection
  # Changed: Added lapsed route for Module 4 dead-end page.
  # Why: When a specific_date NDA has expired, LPs see a dead-end page (no re-accept possible).
  get :lapsed, on: :collection
  # Changed: Module 9 — blocked page route for non-signatories.
  # Why: Non-signatory LPs are redirected here when the NDA is not yet accepted
  #   and they are not a designated signatory. Dead-end page with no accept/decline buttons.
  get :blocked, on: :collection
end

# Changed: NDA status dashboard routes — removed exemption routes.
# Why: Exemption is now a boolean on InvestorAccess (stakeholder-level),
#   managed from InvestorAccess form, not from the NDA dashboard.
get  "nda_status/summary",       controller: "nda_status", action: :summary, as: :nda_status_summary
get  "nda_status",               controller: "nda_status", action: :index, as: :nda_status
# Changed: Added signatory routes for tag/untag actions.
# Why: Per-NDA signatory designation replaces entity-wide InvestorAccess tag_list.
post   "nda_status/signatories",     controller: "nda_status", action: :create_signatory, as: :nda_status_signatories
delete "nda_status/signatories/:id", controller: "nda_status", action: :destroy_signatory, as: :nda_status_signatory

# Changed: Module 8 — added revoke and send_reminders routes.
# Why: GP can revoke an accepted investor's NDA and send bulk reminders to pending
#   investors from the NDA Status Dashboard.
post "nda_status/revoke",          controller: "nda_status", action: :revoke,          as: :nda_status_revoke
post "nda_status/send_reminders",  controller: "nda_status", action: :send_reminders,  as: :nda_status_send_reminders

# Workflow instances are standalone — not nested under any workflowable object.
# workflowable_type and workflowable_id are passed as params on create.
resources :workflow_instances, only: %i[index create show] do
  member do
    post :advance             # admin sets resolved state (tiebreaker / override)
    post :reset               # admin resets to step 1
    post :archive             # admin archives a stalled instance
    post :send_reminder       # admin triggers immediate reminder to pending actors
    get  :export_audit_trail  # download full state-change history as CSV
    post :acknowledge         # "Mark reviewed" on a journey's current acknowledge step
    get  :step_info           # a journey step's popup (what to do, what happens, why)
  end

  # Actor responses nested under their instance (no folder nesting)
  resources :workflow_actor_responses, only: %i[create]
end

resources :investor_accesses do
  get 'search', on: :collection
  patch 'approve', on: :member
  post 'request_access', on: :collection
  post 'upload', on: :collection
end
resources :access_rights do
  get 'search', on: :collection
end
resources :notifications do
  patch 'mark_as_read', on: :member
end

resources :messages do
  post 'mark_as_task', on: :member
  patch 'task_done', on: :member
end

resources :notes do
  get 'search', on: :collection
end

resources :shareholder_positions, only: [:index] do
  patch 'approve', on: :member
  delete 'reject', on: :member
  patch 'approve_all', on: :collection
end

resources :investors do
  get 'analytics', on: :collection
  get 'portfolio_analytics', on: :member
  get 'search', on: :collection

  get 'merge', on: :collection
  post 'merge', on: :collection
  get 'dashboard', on: :member
  # Route to return a report detail partial/modal for portfolio agent run links
  get  'generate_reports', on: :member   # step 1: configure form
  post 'generate_reports', on: :member   # step 1: submit → create draft
  get  'kpi_data_preview', on: :member   # AJAX: how many KPI periods are available
  get 'generate_agent_charts', on: :member
  post 'generate_agent_charts', on: :member
  get 'portfolio_investments_report', on: :member
  post 'portfolio_investments_report', on: :member
  get 'portfolio_investments_report_all', on: :collection
  post 'portfolio_investments_report_all', on: :collection
  put 'restore_deleted', on: :member
  get 'show_deleted', on: :collection
  get 'report_detail', on: :collection
  get 'multi_portfolio_stat_currency', on: :collection
  # NDA Module 3 — investor-level exemption toggle (bulk-updates InvestorAccess records)
  patch 'toggle_nda_exemption', on: :member
  # LP folio portfolio — company-level Show / Hide from LPs
  patch 'lp_sharing', on: :member
end

resources :investor_notice_entries
resources :investor_notices
resources :fees

resources :documents do
  post 'run_fix', on: :member
  patch 'send_for_esign', on: :member
  patch 'force_send_for_esign', on: :member
  patch 'cancel_esign', on: :member
  patch 'extend_esign_expiry', on: :member
  patch 'send_esign_reminder', on: :member
  patch 'resend_for_esign', on: :member
  patch 'send_all_for_esign', on: :collection
  post 'signature_progress', on: :collection
  post 'download', on: :collection
  post 'fetch_esign_updates', on: :member
  get 'search', on: :collection
  get 'investor', on: :collection
  get 'folder', on: :collection
  get 'owner', on: :collection
  get 'approve', on: :collection
  post 'approve', on: :collection
  post 'bulk_actions', on: :collection
  patch 'send_document_notification', on: :member
  post 'share_by_email', on: :member # New route for sharing documents by email
  get 'show_file', on: :member
  get 'show_email_list', on: :member # New route for showing email list
  get 'row_actions', on: :member # Edit/Delete items of a list row's Actions menu, loaded when it opens
  put 'restore_deleted', on: :member
  get 'show_deleted', on: :collection
  get 'verify_accessibility', on: :member # New route for verifying PDF accessibility
end

# Top-level route for viewing shared documents
resources :doc_shares do
  get 'view', on: :collection
end

# Workflow magic-link routes — no auth required; the signed token is the credential
get  'workflow_magic_links/:token',        to: 'workflow_magic_link#show',   as: :workflow_magic_link
post 'workflow_magic_links/:token/submit', to: 'workflow_magic_link#submit', as: :submit_workflow_magic_link

resources :entities do
  get 'search', on: :collection
  # No `report` member route: it rendered any entities/ template named in params[:report] behind an
  # always-true policy, and its only caller was removed in Oct 2025 (H16-1, H16-2 in
  # features/security/entity_report.feature).
  get 'investor_entities', on: :collection
  get 'dashboard', on: :collection
  get 'investor_view', on: :member
  post 'delete_attachment', on: :collection
  post 'kpi_reminder', on: :member
  patch 'add_sebi_fields', on: :member
  patch 'remove_sebi_fields', on: :member
  get 'merge', on: :collection
  post 'merge', on: :collection
  post 'db_dump', on: :member
  # Support-only off-boarding: revokes employee logins and investor access for the entity
  patch 'deactivate', on: :member
  # The company's own Zoho Sign account (openspec/changes/zoho-esign-production-ready, card ①)
  resource :zoho_sign_connection, only: %i[create update destroy] do
    post :verify
    post :reveal_webhook_secret
    post :regenerate_webhook_secret
  end
end

# Zoho Sign webhooks for a company's own account - authenticated by token + HMAC, not a session
post 'zoho_sign/webhooks/:token', to: 'zoho_sign_webhooks#create', as: :zoho_sign_webhook

resources :viewed_bies do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :dashboard_widgets do
  # LP folio portfolio — LP layouts of the Portfolio Company Dashboard
  post 'setup_lp_layout', on: :collection
  post 'new_lp_layout', on: :collection
  get 'dashboard', on: :collection
  get 'metadata_help', on: :collection
  # Widget settings in place — openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings (D2)
  get 'settings', on: :collection
  patch 'save_settings', on: :collection
end

# Document Checks — openspec/changes/document-checks/design.md (cards ①, ③, ⑧)
resources :doc_checks, only: %i[index] do
  collection do
    patch :save_document
    post :add_recommended
    post :trial
  end
end
resources :doc_check_runs, only: %i[create show] do
  get :panel, on: :collection
end
resources :doc_check_results, only: %i[index] do
  member do
    patch :use_document_value
    patch :mark_ok
    patch :undo
  end
  post :check_again, on: :collection
end
