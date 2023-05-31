json.extract! kyc_data, :id, :entity_id, :investor_kyc_id, :source, :response
json.url kyc_data_url(kyc_data, format: :json)
