class VerifyKycPanJob < VerifyPanJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @model = InvestorKyc.find(id)
      if @model.entity.entity_setting.pan_verification
        verify
        @model.save
      else
        Rails.logger.debug { "Skipping: pan_verification set to false for #{@model.entity.name}" }
      end
    end
  end
end
