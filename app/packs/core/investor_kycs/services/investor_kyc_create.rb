class InvestorKycCreate < InvestorKycAction
  step :save
  step :associate_with_owner
  left :handle_errors, Output(:failure) => End(:failure)
  step :fix_folder_paths
  step :send_kyc_form_on_create
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :updated_notification

  # This method is used to generate the AML report for the investor_kyc
  def generate_aml_report(ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report(ctx[:user_id]) if investor_kyc.full_name.present? && ctx[:user_id].present? && investor_kyc.entity.entity_setting.aml_enabled
    true
  end

  # This method is used to save the investor_kyc to the associated owner like capital_commitment or expression_of_interest
  # rubocop:disable Rails/SkipsModelValidations
  def associate_with_owner(ctx, investor_kyc:, **)
    if ctx[:owner_id].present? && ctx[:owner_type].present?
      owner = ctx[:owner_type].constantize.find(ctx[:owner_id])
      owner.update_columns(investor_kyc_id: investor_kyc.id)
    end
    true
  end
  # rubocop:enable Rails/SkipsModelValidations
end
