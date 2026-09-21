# Runs one step of a FundFormulaOperation in the background: previewing (planning, which may load a full
# scratch copy of the fund or test-run check suggestions) or applying a previewed plan.
#
#   FundFormulaOperationJob.perform_later(operation.id, "preview")
#   FundFormulaOperationJob.perform_later(operation.id, "apply")
#
# Formula edits are audited as the user who asked for the step. Every outcome is written back to the
# operation, and the user is told when it finishes; nothing is retried.
class FundFormulaOperationJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 0

  def perform(operation_id, step)
    operation = FundFormulaOperation.find_by(id: operation_id)
    return if operation.nil?

    user = step == "apply" ? operation.applied_by : operation.requested_by
    Chewy.strategy(:bypass) do
      Audited.audit_class.as_user(user) { step == "apply" ? apply(operation) : preview(operation) }
    end
    notify(operation.reload, user)
  end

  private

  def preview(operation)
    plan = operation.suggestions? ? suggestion_plan(operation) : migration(operation).plan_for(operation.operation, operation.params).to_h
    operation.update!(plan:, status: preview_status(operation, plan), previewed_at: Time.current, error: nil)
  rescue StandardError => e
    fail!(operation, e)
  end

  def apply(operation)
    # Only the request that set "applying" (FundFormulaOperation#start_apply!) has a job to run; a job
    # arriving for an operation already applied, refused or failed must not write on top of it
    return unless operation.applying?

    reason = FundAllocationActivity.new(operation.fund).reason(except: operation)
    return operation.update!(status: "refused", error: reason) if reason

    plan = AccountEntryAllocation::IncrementalMigration::Plan.from_h(operation.plan)
    result = migration(operation).apply!(plan)
    operation.update!(status: "applied", result:, applied_at: Time.current, error: nil)
  rescue AccountEntryAllocation::IncrementalMigration::PlanChanged, AccountEntryAllocation::IncrementalMigration::NotApplicable => e
    operation.update!(status: "refused", error: e.message)
  rescue StandardError => e
    fail!(operation, e)
  end

  def migration(operation)
    AccountEntryAllocation::IncrementalMigration.new(operation.fund, out: StringIO.new)
  end

  # Rules always; AI too when asked. Every suggestion is test-run against the last successful run.
  def suggestion_plan(operation)
    builder = AccountEntryAllocation::RunCheckSuggestions::Builder.new(operation.fund)
    suggestions = builder.suggestions
    ai = nil
    if operation.params.to_h["ai"]
      ai = AccountEntryAllocation::RunCheckSuggestions::AiSuggester.new(builder, existing: suggestions).call
      suggestions += ai[:accepted]
    end
    builder.test_run(suggestions)
    run = builder.context.last_successful_run
    { "suggestions" => suggestions.map(&:to_h), "ai_requested" => ai.present?, "ai_error" => ai&.dig(:error),
      "rejected" => ai&.dig(:rejected) || [], "tested_against_run_id" => run&.id }
  end

  # A plan with nothing to write (blocked, already on, nothing to restore or recompute) cannot be applied
  def preview_status(operation, plan)
    return "previewed" if operation.suggestions?

    plan = AccountEntryAllocation::IncrementalMigration::Plan.from_h(plan)
    plan.blocked? || plan.already_enabled? || !plan.changes? ? "blocked" : "previewed"
  end

  def fail!(operation, error)
    Rails.logger.error { "FundFormulaOperationJob: operation #{operation.id} #{error.class}: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}" }
    operation.update!(status: "failed", error: "#{error.class}: #{error.message}".truncate(2000))
  end

  def notify(operation, user)
    return unless user

    level = { "previewed" => "success", "applied" => "success", "blocked" => "warning" }.fetch(operation.status, "danger")
    UserAlert.new(user_id: user.id, level:,
                  message: "#{operation} on #{operation.fund.name}: #{operation.status}#{" - #{operation.error.truncate(200)}" if operation.error.present?}").broadcast
  end
end
