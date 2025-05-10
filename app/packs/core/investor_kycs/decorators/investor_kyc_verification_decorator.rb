class InvestorKycVerificationDecorator < ApplicationDecorator
  def bank_verification_enabled?
    entity.entity_setting.bank_verification
  end

  def pan_verification_enabled?
    entity.entity_setting.pan_verification
  end
end
