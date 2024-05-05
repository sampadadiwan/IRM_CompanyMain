class VerifyKycBankJob < VerifyBankJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:active_job) do
      @model = InvestorKyc.find(id)
      if @model.entity.entity_setting.bank_verification
        verify
        @model.save(validate: false)
      else
        Rails.logger.debug { "Skipping: bank_verification set to false for #{@model.entity.name}" }
      end
    end
  end
end
