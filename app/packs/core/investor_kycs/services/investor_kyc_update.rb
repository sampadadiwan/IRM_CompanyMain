class InvestorKycUpdate < InvestorKycAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :send_kyc_form
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :updated_notification
  step :update_kyc_data

  def update_kyc_data(_ctx, investor_kyc:, **)
    return true if investor_kyc.destroyed?
    return true if investor_kyc.kyc_datas.blank?

    # Update KYC data with the latest information from investor_kyc
    investor_kyc.kyc_datas.where(PAN: investor_kyc.PAN).find_each do |kyc_data|
      kyc_data.update(
        PAN: investor_kyc.PAN,
        birth_date: investor_kyc.birth_date
      )
    end
    true
  end

  def generate_aml_report(ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report(ctx[:user_id]) if investor_kyc.full_name_has_changed? && ctx[:user_id].present?
    true
  end
end
