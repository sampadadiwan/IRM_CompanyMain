class InvestorKycUpdate < InvestorKycAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :send_kyc_form
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :generate_aml_report
  step :updated_notification
  step :create_investor_kyc_sebi_data
  step :handle_kyc_sebi_data_errors

  def generate_aml_report(_ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report if investor_kyc.full_name_has_changed?
    true
  end
end
