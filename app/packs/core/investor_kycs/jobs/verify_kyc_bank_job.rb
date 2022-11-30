class VerifyKycBankJob < VerifyBankJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:atomic) do
      @model = InvestorKyc.find(id)
      verify
      @model.save
    end
  end
end
