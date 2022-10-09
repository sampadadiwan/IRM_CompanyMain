class VerifyKycBankJob < VerifyBankJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @model = InvestorKyc.find(id)
      verify
      @model.save
    end
  end
end
