class InvestorKycAction < Trailblazer::Operation
  def save(ctx, investor_kyc:, **)
    validate = ctx[:investor_user]
    investor_kyc.save(validate:)
  end

  def handle_errors(ctx, investor_kyc:, **)
    unless investor_kyc.valid?
      ctx[:errors] = investor_kyc.errors.full_messages
      Rails.logger.error("Investor KYC errors: #{investor_kyc.errors.full_messages}")
    end
    investor_kyc.valid?
  end

  def validate_bank(_ctx, investor_kyc:, **)
    investor_kyc.validate_bank unless investor_kyc.destroyed?
    true
  end

  def validate_pan_card(_ctx, investor_kyc:, **)
    investor_kyc.validate_pan_card unless investor_kyc.destroyed?
    true
  end

  def enable_kyc(_ctx, investor_kyc:, **)
    investor_kyc.enable_kyc
    true
  end

  def send_kyc_form(_ctx, investor_kyc:, investor_user:, **)
    SendKycFormJob.perform_later(investor_kyc.id) if investor_kyc.saved_change_to_send_kyc_form_to_user? && investor_kyc.send_kyc_form_to_user && !investor_user
    true
  end

  def updated_notification(_ctx, investor_kyc:, investor_user:, **)
    # reload the kyc in case it was changed from individual to non individual or visa versa
    investor_kyc = InvestorKyc.find(investor_kyc.id)
    investor_kyc.updated_notification if investor_user
    true
  end
end
