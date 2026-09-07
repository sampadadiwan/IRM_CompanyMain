# Starts a group run: runs the pre-flight checks again (the page the employee confirmed on
# may be stale), records the AllocationGroupRun with one item per template, and enqueues the
# single background job that runs the templates one after another.
#
#   result = AllocationGroupRunStart.call(group:, user:, start_date:, end_date:, resume: true)
#   result.success? ? result[:group_run] : result[:checks] / result[:group_blockers]
class AllocationGroupRunStart < Trailblazer::Operation
  step :preflight
  step :startable?
  step :record_run
  step :enqueue

  def preflight(ctx, group:, user:, start_date:, end_date:, resume: true, **)
    result = AllocationGroupRunPreflight.call(group:, user:, start_date:, end_date:, resume:)
    ctx[:checks] = result[:checks]
    ctx[:group_blockers] = result[:group_blockers]
    ctx[:startable] = result[:startable]
    ctx[:resume_from] = result[:resume_from]
    true
  end

  def startable?(ctx, startable:, **)
    ctx[:error] = "The group cannot start: fix the blocked templates and check again." unless startable
    startable
  end

  # Everything is written in one transaction so a half-recorded run can never be picked up
  # by the job. The preflight's "one active run per entity" check ran outside any lock, so
  # two concurrent requests could both see no active run and both reach here — row-locking
  # the entity first serializes them: whichever transaction commits first wins, and the
  # second re-checks active_for_entity while holding the lock and backs out cleanly.
  def record_run(ctx, group:, user:, start_date:, end_date:, checks:, resume_from:, **)
    ctx[:group_run] = AllocationGroupRun.transaction do
      group.entity.lock!

      if (active = AllocationGroupRun.active_for_entity(group.entity_id))
        ctx[:error] = "Another allocation run group is already #{active.status} (#{active}). Wait for it to finish before starting this one."
        raise ActiveRecord::Rollback
      end

      run = AllocationGroupRun.create!(
        entity_id: group.entity_id, user_id: user.id, allocation_run_template_group: group,
        group_name: group.name, start_date:, end_date:, status: "queued", resumed_from: resume_from
      )
      checks.each do |check|
        run.items.create!(
          allocation_run_template: check.template, fund: check.fund, template_name: check.template.name,
          position: check.position,
          status: check.reused? ? "reused" : "pending",
          allocation_run: check.reused_run,
          message: (check.messages.first&.text if check.reused?)
        )
      end
      run
    end
    ctx[:group_run].present?
  end

  def enqueue(_ctx, group_run:, **)
    AllocationGroupRunJob.perform_later(group_run.id)
    true
  end
end
