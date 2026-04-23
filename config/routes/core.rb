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
  get    ':id/edit',                 action: :edit,              as: :edit_report_builder
  get    ':id/preview',              action: :preview,           as: :preview_report_builder
  get    ':id/download',             action: :download,          as: :download_report_builder
  patch  ':id/template',             action: :update_template,   as: :update_report_builder_template
  post   ':id/columns',              action: :add_column,        as: :add_report_builder_column
  delete ':id/columns/:gvp_id',      action: :remove_column,     as: :remove_report_builder_column
  post   ':id/join',                 action: :add_join,          as: :add_report_builder_join
  delete ':id/join',                 action: :remove_join,       as: :remove_report_builder_join
  patch  ':id/aggregate',            action: :update_aggregate,  as: :update_report_builder_aggregate
  patch  ':id/sort',                 action: :update_sort,       as: :update_report_builder_sort
  patch  ':id/name',                 action: :update_name,       as: :update_report_builder_name
  patch  ':id/pivot',                action: :update_pivot,      as: :update_report_builder_pivot
end

resources :report_insights
resources :audits
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
  delete 'destroy_series', on: :member
end

resources :form_custom_fields do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :form_types do
  get 'clone', on: :member
  patch 'rename_fcf', on: :member
  patch 'add_regulatory_fields', on: :member
  get 'generate_upload_xlsx', on: :member
end

resources :e_signatures
resources :stamp_papers
resources :investor_notice_items
resources :exchange_rates do
  post 'generate_tracking_numbers', on: :member
end

resources :approval_responses do
  patch 'approve', on: :member
  get 'email_response', on: :member
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
  get 'preview', on: :member
  get 'search', on: :collection
  put 'toggle_verified', on: :member
  patch 'send_notification', on: :member
  post 'send_kyc_reminder', on: :member
  post 'notify_kyc_required', on: :member
  post 'send_kyc_reminder_to_all', on: :collection
  put 'generate_new_aml_report', on: :member
  post 'compare_kyc_datas', on: :collection
  put 'assign_kyc_data', on: :member
  get 'edit_my_kyc', on: :collection
  get 'generate_docs', on: :member # Just show the form
  patch 'generate_docs', on: :member # Actually generate the docs
  get 'generate_all_docs', on: :collection
  post 'generate_all_docs', on: :collection # Generate docs for entire fund or entity
  post 'bulk_actions', on: :collection
  post 'validate_docs_with_ai', on: :member
  post 'create_and_send_kyc_to_investor', on: :collection
  get "download_kra_data", on: :member
  get "fetch_ckyc_data", on: :member
  get 'esign_emails', on: :collection
  get 'edit_reporting_fields', on: :member
  put 'update_reporting_fields', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :aml_reports do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :kyc_datas do
  get 'search', on: :collection
  get 'fetch_ckyc_data', on: :collection
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

resources :folders do
  get 'download', on: :member
  post 'generate_report', on: :member
  get 'generate_report', on: :member
  get 'data_rooms', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
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

resources :investors do
  get 'analytics', on: :collection
  get 'search', on: :collection

  get 'merge', on: :collection
  post 'merge', on: :collection
  get 'dashboard', on: :member
  # Route to return a report detail partial/modal for portfolio agent run links
  get 'generate_reports', on: :member
  post 'generate_reports', on: :member
  get 'portfolio_investments_report', on: :member
  post 'portfolio_investments_report', on: :member
  get 'portfolio_investments_report_all', on: :collection
  post 'portfolio_investments_report_all', on: :collection
  put 'restore_deleted', on: :member
  get 'show_deleted', on: :collection
  get 'report_detail', on: :collection
end

resources :investor_notice_entries
resources :investor_notices
resources :fees

resources :documents do
  patch 'send_for_esign', on: :member
  patch 'force_send_for_esign', on: :member
  patch 'cancel_esign', on: :member
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
  put 'restore_deleted', on: :member
  get 'show_deleted', on: :collection
end

# Top-level route for viewing shared documents
resources :doc_shares do
  get 'view', on: :collection
end

resources :entities do
  get 'search', on: :collection
  get 'report', on: :member
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
end

resources :viewed_bies do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :dashboard_widgets do
  get 'dashboard', on: :collection
  get 'metadata_help', on: :collection
end
resources :doc_questions do
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
