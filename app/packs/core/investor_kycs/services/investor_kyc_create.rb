class InvestorKycCreate < InvestorKycAction
  step :save
  left :handle_errors
  step :create_investor_kyc_sebi_data
  step :handle_kyc_sebi_data_errors
  step :send_kyc_form
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :generate_aml_report
  step :updated_notification

  def generate_aml_report(_ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report if investor_kyc.full_name.present?
    true
  end
end
