# phase 9 (#18 H31): :pan_card_data is no column of investor_kycs — extracting it made every KYC JSON a 500
json.extract! investor_kyc, :id, :investor_id, :entity_id, :full_name, :birth_date, :PAN, :address, :bank_account_number, :ifsc_code, :bank_verified, :bank_verification_response, :bank_verification_status, :signature_data, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :created_at, :updated_at
json.url investor_kyc_url(investor_kyc, format: :json)

# KYC status for the LP mobile app's KYC screens: where the form stands, and whether the investor may
# ask the GP for changes (InvestorKycPolicy#send_notification? — submitted or verified only)
json.kyc_type investor_kyc.kyc_type
json.submission_status investor_kyc.submission_status
json.verified investor_kyc.verified
json.docs_completed investor_kyc.docs_completed
json.can_request_updates policy(investor_kyc).send_notification? if current_user.curr_role == "investor"
