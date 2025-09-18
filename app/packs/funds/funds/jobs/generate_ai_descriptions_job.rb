# app/packs/funds/funds/jobs/generate_ai_descriptions_job.rb
# This background job is responsible for generating AI-powered explanations for all
# fund formulas associated with a specific fund. It is designed to be idempotent,
# skipping formulas that already have an AI-generated description.
class GenerateAiDescriptionsJob < ApplicationJob
  queue_as :default

  # @param fund_formula_ids [Array] The IDs of the fund formulas that need descriptions.
  # @param user_id [Integer, nil] The ID of the user who initiated the job, for notifications.
  def perform(fund_formula_ids, user_id = nil)
    Chewy.strategy(:sidekiq) do
      formulas = FundFormula.where(id: fund_formula_ids).order(sequence: :asc)
      formulas_wo_descriptions = formulas.without_ai_description
      # For multiple formulas, only process those without an AI description
      formulas = formulas_wo_descriptions if formulas.size > 1

      # Show proper notification
      if formulas.empty?
        msg = "No Formulas found without descriptions"
        notify_user(msg, :info, user_id)
        Rails.logger.info msg
      else
        msg = "Generating AI Descriptions for #{formulas.count} formulas"
        notify_user(msg, :info, user_id)
      end

      # Process each formulas that requires an AI description.
      process_formulas(formulas, user_id)

      notify_user("✅ AI Descriptions generation completed for #{formulas.size} formulas", :success, user_id)
    end
  end

  private

  # Processes each fund formula that requires an AI description.
  # @param formulas [ActiveRecord::Relation] The formulas to process.
  # @param user_id [Integer, nil] The user to notify of progress and errors.
  def process_formulas(formulas, user_id)
    formulas.each do |formula|
      process_formula(formula, user_id)
    end
  end

  # Processes a single fund formula to generate its AI description.
  # @param formula [FundFormula] The formula to process.
  # @param user_id [Integer, nil] The user to notify of progress and errors
  def process_formula(formula, user_id)
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
