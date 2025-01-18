class InvestorKycCreate < InvestorKycAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :fix_folder_paths
  step :send_kyc_form_on_create
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :updated_notification

  def generate_aml_report(ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report(ctx[:user_id]) if investor_kyc.full_name.present? && ctx[:user_id].present? && investor_kyc.entity.entity_setting.aml_enabled
    true
  end
end
