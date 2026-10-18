json.extract! import_upload, :id, :name, :entity_id, :owner_id, :owner_type, :user_id, :import_type, :status, :error_text, :created_at, :updated_at
json.url import_upload_url(import_upload, format: :json)

# Outcome of the import, for the client-onboarding agent (funds-json-api-hardening phase 3, G8 — H16 E23).
# Nothing new is exposed: the upload's page already shows these counts and links the results file.
json.extract! import_upload, :total_rows_count, :processed_row_count, :failed_row_count, :custom_fields_created
json.results_url import_upload.import_results&.url
# What happened and why (P1, Orios trial — H20 H21 E25 E26): a derived outcome next to the unchanged
# status, and the first failed rows with their messages
json.outcome import_upload.outcome
# A successful upload's status message (e.g. some remittances not verified) — null otherwise (E33)
json.warning import_upload.warning
json.row_errors import_upload.row_errors || []
