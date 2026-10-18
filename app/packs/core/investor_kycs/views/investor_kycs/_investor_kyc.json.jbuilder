# phase 9 (#18 H31): :pan_card_data is no column of investor_kycs — extracting it made every KYC JSON a 500
json.extract! investor_kyc, :id, :investor_id, :entity_id, :full_name, :birth_date, :PAN, :address, :bank_account_number, :ifsc_code, :bank_verified, :bank_verification_response, :bank_verification_status, :signature_data, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :created_at, :updated_at
json.url investor_kyc_url(investor_kyc, format: :json)
