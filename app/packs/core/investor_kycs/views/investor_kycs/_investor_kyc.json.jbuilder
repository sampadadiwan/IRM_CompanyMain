json.extract! investor_kyc, :id, :investor_id, :entity_id, :full_name, :birth_date, :PAN, :address, :bank_account_number, :ifsc_code, :bank_verified, :bank_verification_response, :bank_verification_status, :signature_data, :pan_card_data, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :created_at, :updated_at
json.url investor_kyc_url(investor_kyc, format: :json)
