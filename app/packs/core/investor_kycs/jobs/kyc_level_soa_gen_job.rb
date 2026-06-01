class KycLevelSoaGenJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 0

  def perform(commitment_ids:, template_id:, start_date:, end_date:, user_id:)
    @error_msg = []
    Chewy.strategy(:sidekiq) do
      CapitalCommitment.where(id: commitment_ids).find_each do |commitment|
        if commitment.skip_doc_gen?
          @error_msg << { msg: "Commitment #{commitment} is marked to skip document generation", model: commitment.to_s }
          next
        elsif commitment.investor_kyc.blank?
          @error_msg << { msg: "Commitment #{commitment} has no associated investor KYC", model: commitment.to_s }
          next
        elsif !commitment.investor_kyc.verified?
          @error_msg << { msg: "Commitment #{commitment} has an associated investor KYC that is not verified", model: commitment.to_s }
          next
        end
        KycDocGenJob.perform_now(
          commitment.investor_kyc_id,
          template_id,
          start_date,
          end_date,
          user_id,
          entity_id: commitment.entity_id,
          options: { capital_commitment_id: commitment.id, fund_id: commitment.fund_id, generate_per_kyc: true }
        )
      end
    end
    notify_user(user_id, start_date, end_date)
  end

  def notify_user(user_id, start_date, end_date)
    # Send email if there are any errors
    if @error_msg.present?
      @main_error = "Investor Statement generation for #{start_date} - #{end_date} completed with #{@error_msg.length} errors."
      @user_id = user_id
      email_errors
      send_errors_notification("Investor Statement generation for #{start_date} - #{end_date} completed with #{@error_msg.length} errors. Error email sent with details.", @error_msg, user_id, "danger")
    else
      msg = "Done generating Entity Level Investor Statement for #{start_date} - #{end_date}"
      logger.info msg
      send_notification(msg, user_id, "success")
    end
    @error_msg
  end
end
