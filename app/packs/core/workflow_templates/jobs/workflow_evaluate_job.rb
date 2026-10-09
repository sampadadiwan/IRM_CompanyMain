# The 15-minute tick (capital-call-journey). Re-evaluates every journey so progress made without
# anyone looking — a payment recorded, notices approved on the Documents screen, a background job
# finishing — is picked up, and approvers of a newly current human step are emailed promptly.
#
# Scope: evaluated instances only (human-only approval workflows never match), active ones plus
# complete ones within WorkflowEvaluator::COMPLETE_HORIZON so a late undo is still noticed.
# Passive: never resets sign-offs and never sends reminders (WorkflowAutoReminderJob does that daily).
# No retries: the next tick is the retry.
# Worked examples H16, H17, E28 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
class WorkflowEvaluateJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 0

  def perform
    Chewy.strategy(:sidekiq) do
      scope.find_each do |instance|
        WorkflowEvaluator.call(instance:, cause: :progress)
      rescue ActiveRecord::RecordNotFound => e
        # The workflowable was deleted between selection and evaluation
        Rails.logger.info("[WorkflowEvaluateJob] instance #{instance.id} skipped: #{e.message}")
      rescue StandardError => e
        # One bad journey must not stop the others
        Rails.logger.error("[WorkflowEvaluateJob] instance #{instance.id}: #{e.class} – #{e.message}")
        ErrorReport.notify(e, job: self, instance_id: instance.id, entity_id: instance.entity_id,
                              record: "#{instance.workflowable_type}##{instance.workflowable_id}")
      end
    end
  end

  private

  def scope
    complete_cutoff = WorkflowEvaluator::COMPLETE_HORIZON.ago
    WorkflowInstance.evaluated
                    .where(status: WorkflowInstance.statuses[:active])
                    .or(WorkflowInstance.evaluated.where(status: WorkflowInstance.statuses[:complete])
                                                  .where(completed_at: complete_cutoff..))
  end
end
