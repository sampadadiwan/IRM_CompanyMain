resources :quick_link_steps
resources :quick_links
resources :custom_notifications

resources :reports do
  post 'prompt', on: :collection
  get 'dynamic', on: :member
end

resources :audits
resources :reminders
resources :favorites

resources :permissions

resources :task_templates do
  post 'generate', on: :collection
end

resources :tasks do
  get 'search', on: :collection
  patch 'completed', on: :member
end

resources :form_custom_fields

resources :form_types do
  get 'clone', on: :member
  patch 'rename_fcf', on: :member
  patch 'add_regulatory_fields', on: :member
end

resources :e_signatures
resources :stamp_papers
resources :investor_notice_items
resources :exchange_rates

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
end

resources :aml_reports

resources :kyc_datas do
  get 'search', on: :collection
  get 'fetch_ckyc_data', on: :collection
  get 'send_ckyc_otp', on: :member
  put 'download_ckyc_with_otp', on: :member
  put 'refresh', on: :member
  get 'compare_ckyc_kra', on: :collection
end

resources :video_kycs do
  get 'search', on: :collection
end

resources :payments
resources :nudges
resources :import_uploads do
  delete 'delete_data', on: :member
end

resources :folders do
  get 'download', on: :member
  post 'generate_report', on: :member
  get 'generate_report', on: :member
  get 'data_rooms', on: :collection
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
  get 'search', on: :collection
  get 'merge', on: :collection
  post 'merge', on: :collection
  get 'dashboard', on: :member
  get 'generate_reports', on: :member
  post 'generate_reports', on: :member
  get 'portfolio_investments_report', on: :member
  post 'portfolio_investments_report', on: :member
  get 'portfolio_investments_report_all', on: :collection
  post 'portfolio_investments_report_all', on: :collection
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
end

resources :viewed_bies

resources :dashboard_widgets do
  get 'dashboard', on: :collection
  get 'metadata_help', on: :collection
end
resources :incoming_emails
resources :doc_questions
