class CapitalCommitmentGenerateEsignJob < ApplicationJob
    queue_as :default
  
    # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
    def perform(capital_commitment_id)
      Chewy.strategy(:sidekiq) do
        @capital_commitment = CapitalCommitment.find(capital_commitment_id)
        CapitalCommitmentEsignProvider.new(@capital_commitment).trigger_signatures 
      end       
    end
end
  