class FundCapitalCommitmentDocJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, user_id = nil, template_name: nil)
    fund = Fund.find(fund_id)
    error_msg = []
    Chewy.strategy(:sidekiq) do
      # Need to generate docs for all commitments of the fund
      fund.capital_commitments.each do |capital_commitment|
        errors = CapitalCommitmentDocJob.perform_now(capital_commitment.id, user_id, template_name:)
        error_msg.concat(errors) if errors.present?
      end
    end

    if error_msg.present?
      msg = "Documentation generation completed with errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: fund.entity_id, user_id:, error_msg:).doc_gen_errors.deliver_now
    else
      send_notification("Documentation generation completed.", user_id, :success)
    end
  end
end
