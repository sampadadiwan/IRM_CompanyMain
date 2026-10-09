# Service to pre-create a KPI report "shell" for a portfolio company.
# This shell allows startups to log in and self-report their performance data.
#
# Reference: kpi_portco_upload.md
class KpiReportCreateShell < Trailblazer::Operation
  step :setup_params
  step :check_existence
  step :create_report
  step :notify_users
  step :start_journey

  # Gather all attributes required for the KpiReport model.
  # We assign a default user_id from the Fund entity to act as the initial "creator".
  def setup_params(ctx, entity:, portco:, as_of:, period:, **)
    # Imported periods always resolve to the END of the month/quarter/year (KpiDateUtils), so the
    # request must live on the same date or the portco's data would land on a different report and
    # the requested-period check could never be satisfied. Normalise whatever date the fund typed.
    as_of = as_of.to_date.end_of_month
    ctx[:params] = {
      entity: entity,
      portfolio_company: portco,
      as_of: as_of,
      period: period,
      tag_list: "Actual",
      enable_portco_upload: true,
      user_id: entity.employees.first&.id
    }
  end

  # Idempotency check: Ensure we don't create duplicate shells for the same
  # entity/portco/date/period combination.
  def check_existence(_ctx, entity:, portco:, as_of:, period:, **)
    !KpiReport.exists?(
      entity_id: entity.id,
      portfolio_company_id: portco.id,
      as_of: as_of,
      period: period,
      enable_portco_upload: true,
      tag_list: "Actual"
    )
  end

  # Create the report record. We use `validate: false` because the shell
  # is intentionally incomplete (values will be filled by the startup later).
  def create_report(ctx, params:, **)
    ctx[:model] = KpiReport.new(params)
    ctx[:model].save(validate: false)
  end

  # Trigger notifications for all eligible users at the Portfolio Company.
  # The notifier handles the actual email delivery (KpiReportNotifier).
  def notify_users(_ctx, model:, params:, **)
    notified = params[:portfolio_company].notification_users(model, with_tag: 'Kpi').each do |user|
      KpiReportNotifier.with(record: model, entity_id: params[:entity].id).deliver_later(user)
    end
    # The upload link went out, so record it the way SendPortcoNotification does — the journey's
    # "Send upload request" step reads link_sent_at
    model.update_columns(status: 'link_sent', link_sent_at: Time.current) if notified.any?

    Rails.logger.info "Created KPI Report shell and triggered notifications for #{params[:portfolio_company].investor_name} in #{params[:entity].name}"
    true
  end

  # A shell is a request for the portco's KPIs: it gets the KPI report journey (no email). Never fails
  # the operation. Worked examples H3 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def start_journey(_ctx, model:, **)
    model.start_journey!
    true
  end
end
