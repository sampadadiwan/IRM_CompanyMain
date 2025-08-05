# app/packs/funds/funds/jobs/generate_ai_descriptions_job.rb
# This background job is responsible for generating AI-powered explanations for all
# fund formulas associated with a specific fund. It is designed to be idempotent,
# skipping formulas that already have an AI-generated description.
class GenerateAiDescriptionsJob < ApplicationJob
  queue_as :default

  # @param fund_id [Integer] The ID of the fund whose formulas need descriptions.
  # @param user_id [Integer, nil] The ID of the user who initiated the job, for notifications.
  def perform(fund_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      fund = Fund.find_by(id: fund_id)
      raise "Fund with ID #{fund_id} not found." unless fund

      notify_user("🔍 Generating AI Descriptions for formulas under #{fund.name}", :info, user_id)

      # Process each formulas that requires an AI description.
      formulas = fund.fund_formulas.without_ai_description.order(sequence: :asc)
      process_formulas(formulas, user_id)

      notify_user("✅ AI Descriptions generation completed for #{formulas.size} formulas under #{fund.name}", :success, user_id)
    end
  end

  private

  # Processes each fund formula that requires an AI description.
  # @param formulas [ActiveRecord::Relation] The formulas to process.
  # @param user_id [Integer, nil] The user to notify of progress and errors.
  def process_formulas(formulas, user_id)
    formulas.each do |formula|
      notify_user("🧠 Generating AI description for formula #{formula.name}", :info, user_id)

      description = FundFormulaExplainer.explain(formula)
      formula.update!(ai_description: description)
      Rails.logger.info "✅ Updated formula #{formula.name}"
    rescue StandardError => e
      error_msg = "❌ Error updating formula #{formula.id}: #{e.message}"
      notify_user(error_msg, :error, user_id)
      # Re-raise to allow the job to fail and be retried.
      raise
    end
  end

  # Sends a notification to the user and logs the message.
  # @param message [String] The message to send.
  # @param level [Symbol] The notification level (:info, :error, :success).
  # @param user_id [Integer, nil] The ID of the user to notify.
  def notify_user(message, level, user_id)
    Rails.logger.debug(message)
    return unless user_id

    UserAlert.new(message: message, user_id: user_id, level: level).broadcast
  end
end
