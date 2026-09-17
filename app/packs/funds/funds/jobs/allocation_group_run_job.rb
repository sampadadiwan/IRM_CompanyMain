# Runs every template of an AllocationGroupRun one after another, in position order, in a
# single background job — the next template only starts after the previous one finishes.
#
# Fail early (decision 2): the first template that does not end in Success stops the group;
# the templates after it are marked skipped. A feeder run after a failed master produces
# wrong numbers that then have to be unwound, so carrying on is never useful.
#
# Restart-safe (decision 9): progress is kept per item in the database. If the worker is
# restarted mid-way, Sidekiq re-queues the job and perform resumes from the first item that
# is still pending or running — items already finished are not touched.
class AllocationGroupRunJob < ApplicationJob
  include Rails.application.routes.url_helpers

  queue_as :high
  # Never retry on an exception — every failure is recorded on the run and reported to the
  # employee, and re-running is their explicit decision (the Run button with resume).
  sidekiq_options retry: 0

  def perform(group_run_id)
    group_run = AllocationGroupRun.find_by(id: group_run_id)
    return if group_run.nil? || group_run.finished?

    group_run.update!(status: "running", started_at: group_run.started_at || Time.current)

    failed_item = nil
    group_run.items.ordered.each do |item|
      next if item.finished?

      if failed_item
        item.update!(status: "skipped", finished_at: Time.current,
                     message: "Not run because \"#{failed_item.template_name}\" failed earlier in the group.")
        next
      end

      run_item(group_run, item)
      failed_item = item if item.status == "failed"
    end

    finalize(group_run, failed_item)
  end

  private

  # Creates a new AllocationRun for the template (exactly as a manual run does) and runs the
  # engine synchronously. Any exception is recorded on the item so the group can stop cleanly.
  def run_item(group_run, item)
    template = item.allocation_run_template
    if template.nil?
      item.update!(status: "failed", finished_at: Time.current,
                   message: "The allocation run template was deleted before it could run.")
      return
    end

    item.update!(status: "running", started_at: Time.current, finished_at: nil, message: nil)

    # The pre-flight already evaluated the blocker rules; skip the model-level re-evaluation
    # so the rule engine is not run twice, just as FundsController#allocate does.
    allocation_run = WithValidationRules.skip do
      AllocationRun.create!(template.allocation_run_attributes(start_date: group_run.start_date,
                                                               end_date: group_run.end_date,
                                                               user_id: group_run.user_id)
                                    .merge(skip_fund_busy_check: true)) # this item's own status is already "running" — see AllocationRun#skip_fund_busy_check
    end
    item.update!(allocation_run:)

    result = run_engine(template, group_run, allocation_run)
    allocation_run.reload

    if engine_succeeded?(result, allocation_run, template)
      item.update!(status: "success", finished_at: Time.current)
    else
      item.update!(status: "failed", finished_at: Time.current, message: failure_message(result, allocation_run))
    end
  rescue StandardError => e
    Rails.logger.error("[AllocationGroupRunJob] item #{item.id} (#{item.template_name}) raised: #{e.message}")
    Rails.logger.error(e.backtrace.first(20).join("\n"))
    item.update!(status: "failed", finished_at: Time.current, message: e.message.truncate(2000))
  end

  # Same wrappers as AccountEntryAllocationJob, but the engine result is needed here to
  # decide success, so the engine is called directly rather than through that job.
  def run_engine(template, group_run, allocation_run)
    fund = template.fund
    user = User.find(group_run.user_id)
    options = template.engine_options(user_id: user.id, allocation_run_id: allocation_run.id)
    Chewy.strategy(:bypass) do
      Audited.audit_class.as_user(user) do
        AccountEntryAllocation::Engine.new(fund, group_run.start_date, group_run.end_date, **options).call
      end
    end
  end

  # Decision 7(a): when formulas ran, only an explicit Success counts — a run left at Pending
  # means something did not finish and a feeder must not build on it. A statements-only run
  # never writes Success; the engine only writes a status there when something went wrong.
  def engine_succeeded?(result, allocation_run, template)
    return false if result.respond_to?(:failure?) && result.failure?
    return allocation_run.status == "Success" if template.run_allocations?

    allocation_run.status.blank? || allocation_run.status == "Success"
  end

  def failure_message(result, allocation_run)
    status = allocation_run.status.presence
    return "The allocation run did not finish (status: Pending)." if status == "Pending"
    return status if status.present?

    error = result.respond_to?(:[]) ? result[:error] : nil
    error.presence || "The allocation run failed without recording a reason — see the log."
  end

  # Records the outcome and tells the employee once, in-app and by email (decision 19(b)).
  def finalize(group_run, failed_item)
    if failed_item
      group_run.update!(status: "failed", finished_at: Time.current,
                        message: "Stopped at \"#{failed_item.template_name}\": #{failed_item.message}")
    else
      group_run.update!(status: "success", finished_at: Time.current, message: nil)
    end

    notify_in_app(group_run)
    AllocationGroupRunMailer.with(allocation_group_run_id: group_run.id).completed.deliver_later
  end

  def notify_in_app(group_run)
    h = ActionController::Base.helpers
    counts = group_run.counts_by_status
    summary = %w[success reused failed skipped].filter_map do |s|
      counts[s] ? "#{counts[s]} #{s}" : nil
    end.join(", ")
    link = h.link_to("View progress", allocation_group_run_path(group_run),
                     class: "mb-1 badge bg-primary-subtle text-primary", target: "_blank", rel: "noopener")
    verb = group_run.success? ? "finished successfully" : "stopped after a failure"
    message = "Allocation run group \"#{h.sanitize(group_run.group_name)}\" #{verb} (#{summary}). #{link}"
    UserAlert.new(user_id: group_run.user_id, message:, level: group_run.success? ? "success" : "danger").broadcast
  end
end
