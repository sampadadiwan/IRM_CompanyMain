resources :reminders
resources :permissions
resources :tasks do
  get 'search', on: :collection
  patch 'completed', on: :member
end
resources :form_custom_fields
resources :form_types

resources :e_signatures
resources :stamp_papers
resources :investor_notice_items
resources :exchange_rates

resources :approval_responses do
  patch 'approve', on: :member
end
resources :approvals do
  patch 'approve', on: :member
  patch 'send_reminder', on: :member
end

resources :investor_kycs do
  get 'search', on: :collection
  put 'toggle_verified', on: :member
  get 'send_kyc_reminder', on: :member
  get 'send_kyc_reminder_to_all', on: :collection
  put 'generate_new_aml_report', on: :member
  post 'compare_kyc_datas', on: :collection
  put 'assign_kyc_data', on: :member
  get 'edit_my_kyc', on: :collection
  get 'generate_docs', on: :member # Just show the form
  patch 'generate_docs', on: :member # Actually generate the docs
  get 'generate_all_docs', on: :collection
  post 'generate_all_docs', on: :collection # Generate docs for entire fund or entity
end

resources :aml_reports do
  get 'search', on: :collection
  post 'generate_new', on: :collection
  put 'toggle_approved', on: :member
end

resources :kyc_datas do
  get 'search', on: :collection
  post 'generate_new', on: :collection
  get 'compare_ckyc_kra', on: :collection
end

resources :video_kycs do
  get 'search', on: :collection
end

resources :payments
resources :nudges
resources :import_uploads

resources :folders do
  get 'download', on: :member
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
  get 'mark_as_read', on: :member
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
end

resources :investor_notice_entries
resources :investor_notices
resources :fees

resources :documents do
  patch 'send_for_esign', on: :member
  patch 'force_send_for_esign', on: :member
  patch 'cancel_esign', on: :member
  patch 'send_all_for_esign', on: :collection
  post 'signature_progress', on: :collection
  get 'fetch_esign_updates', on: :member
  get 'search', on: :collection
  get 'investor', on: :collection
  get 'folder', on: :collection
  get 'owner', on: :collection
  get 'approve', on: :collection
  post 'approve', on: :collection
end

resources :entities do
  get 'search', on: :collection
  get 'investor_entities', on: :collection
  get 'dashboard', on: :collection
  get 'investor_view', on: :member
  post 'delete_attachment', on: :collection
end
