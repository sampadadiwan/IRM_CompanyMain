class InterestDecorator < Draper::Decorator
  delegate_all

  def full_name
    buyer_entity_name
  end

  def bank_verification_enabled?
    entity.entity_setting.bank_verification && !secondary_sale.disable_bank_kyc
  end

  def pan_verification_enabled?
    entity.entity_setting.pan_verification && !secondary_sale.disable_pan_kyc
  end
end
