class FundCapitalCommitmentDocJob < ApplicationJob
  queue_as :doc_gen

  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, user_id = nil, template_name: nil)
    Chewy.strategy(:sidekiq) do
      # Need to generate docs for all commitments of the fund
      fund = Fund.find(fund_id)
      fund.capital_commitments.each do |capital_commitment|
        CapitalCommitmentDocJob.perform_later(capital_commitment.id, user_id, template_name:)
      end
    end
  end
end
