# Marks named steps of a record's journey as stale: "the evidence you passed on is no longer good".
# Used by undoing actions whose effect the data alone can't show — e.g. editing a call's figures
# leaves the old notices in place, and editing the email template changes nothing a review can see.
#
# An invalidated system step passes again only on evidence newer than the invalidation (or a
# refresh marker such as "recomputed"); an invalidated acknowledge step needs a new confirmation,
# so its active confirmations are archived here.
#
# Does NOT evaluate: callers run inside Workflowable#journey_undo, which evaluates afterwards with
# cause :undo. A record without a journey, or a journey without these keys, is a silent no-op.
# Worked examples E12, E13, E17, E24 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
class WorkflowStepInvalidate < Trailblazer::Operation
  step :find_instance
  step :invalidate

  def find_instance(ctx, record:, **)
    ctx[:instance] = record.workflow_instances.where(evaluated: true).where.not(status: :archived)
                           .order(created_at: :desc).first
    ctx[:invalidated_positions] = []
    true # no journey → nothing to do, still a success
  end

  # only_if_not_passed: a check key; skip the whole record when the step with that key has passed
  # (e.g. a fund-level email edit must not reopen calls whose notices were already sent)
  def invalidate(ctx, instance:, check_keys:, reason:, actor: nil, only_if_not_passed: nil, **)
    return true unless instance
    return true if only_if_not_passed && step_passed?(instance, only_if_not_passed)

    keys = Array(check_keys).map(&:to_s)
    instance.snapshot_steps.each do |step|
      next unless keys.include?(step[:check_key].to_s)

      position = step[:position].to_i
      WorkflowStateChange.create!(workflow_instance: instance, step_position: position, to_state: "invalidated",
                                  note: reason, actor:, channel: :system)
      # A confirmation made before the change no longer counts
      instance.workflow_actor_responses.active.for_step(position).update_all(archived: true, updated_at: Time.current) if step[:kind].to_s == "acknowledge"
      ctx[:invalidated_positions] << position
    end
    true
  end

  # Records a refresh marker ("recomputed") on the step with check_key: the evidence behind it was
  # renewed, so an earlier invalidation is satisfied (the evaluator treats the marker as fresh
  # evidence). Used by Recompute Call for Create remittances. No-op without a journey.
  def self.record_refresh(record:, check_key:, actor: nil, note: nil)
    instance = record.workflow_instances.where(evaluated: true).where.not(status: :archived).order(created_at: :desc).first
    step = instance&.snapshot_steps&.find { |s| s[:check_key].to_s == check_key.to_s }
    return unless step

    WorkflowStateChange.create!(workflow_instance: instance, step_position: step[:position].to_i, to_state: "recomputed",
                                note:, actor:, channel: :system)
  end

  private

  def step_passed?(instance, check_key)
    step = instance.snapshot_steps.find { |s| s[:check_key].to_s == check_key.to_s }
    step && instance.step_result(step[:position])&.dig("status") == "passed"
  end
end
