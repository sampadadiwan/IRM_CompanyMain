# Backs the KPI grid's Actions → "Approve all". Approving runs ~10 queries per KPI plus each KPI's save
# callbacks (RAG recompute, ...), so a portfolio company with hundreds of staged KPIs could time the web
# request out; the controller now authorises the KPIs and queues this job instead.
#
# Steps, in the order the controller used to run them inline:
#   1. keep only the KPIs still pending (E1 double click / E2 deleted meanwhile: skipped, not an error)
#   2. KpiApproveService - approves them and queues KpiCumulateJob (cumulation + percentage change)
#   3. move the company's KPI report journeys on (H10), which needs the approvals done first
#   4. tell the user who clicked (in-app alert, as RecomputeInvestorKpiMappingRagJob does) - including when
#      nothing was left to approve (E5)
class KpiApproveAllJob < ApplicationJob
  queue_as :default
  # A failure is reported to the user once (the red alert below), as the inline approve failed once. Sidekiq's
  # default 25 retries would re-alert for days on a permanent error such as a KPI failing validation.
  # Deadlocks still retry: ApplicationJob's retry_on ActiveRecord::Deadlocked is ActiveJob's own mechanism.
  sidekiq_options retry: false

  def perform(kpi_ids, user_id, entity_id, portfolio_company_id)
    user = User.find(user_id)
    # The company's name for the alerts (Investor#to_s is not the plain name)
    company_name = Investor.find_by(id: portfolio_company_id)&.investor_name

    # Still pending, in the order the controller listed them (two pending KPIs for the same metric
    # resolve by order - E4)
    pending = Kpi.unapproved.where(id: kpi_ids).pluck(:id).to_set
    @pending_ids = kpi_ids.select { |id| pending.include?(id) }

    KpiApproveService.call(@pending_ids, user_id) if @pending_ids.any?
    KpiReport.journey_progress_for_portco(entity_id, portfolio_company_id, actor: user)

    if @pending_ids.any?
      # The grid the user clicked from still shows the KPIs as pending until it is reloaded
      send_notification("Approved #{@pending_ids.size} KPIs for #{company_name}. Cumulative values are being computed. Refresh the page to see them.", user_id)
    else
      # E5: everything was approved before this run (a double click, or someone else approved them)
      send_notification("Nothing left to approve for #{company_name}. These KPIs were already approved.", user_id)
    end
  rescue ActiveRecord::Deadlocked
    # Not a failure to report: ApplicationJob's retry_on runs the job again, and only the outcome of that run
    # should reach the user (a "stopped" alert now would be followed by "Approved N")
    raise
  rescue StandardError => e
    # E3: what was approved before the failure stays approved; say how far it got
    pending_ids = @pending_ids || []
    done = pending_ids.size - Kpi.unapproved.where(id: pending_ids).count
    send_notification("Approving KPIs for #{company_name} stopped: #{e.message}. #{done} of #{pending_ids.size} were approved.", user_id, "danger")
    raise
  end
end
