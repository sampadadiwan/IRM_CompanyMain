json.extract! aml_report, :id, :investor_id, :entity_id, :investor_kyc_id, :name, :match_status, :approved, :approved_by_id, :types, :source_notes, :associates, :fields, :response
json.url aml_report_url(aml_report, format: :json)
