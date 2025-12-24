# Service to pre-create a KPI report "shell" for a portfolio company.
# This shell allows startups to log in and self-report their performance data.
#
# Reference: kpi_portco_upload.md
class KpiReportCreateShell < Trailblazer::Operation
  step :setup_params
  step :check_existence
  step :create_report
  step :notify_users

  # Gather all attributes required for the KpiReport model.
  # We assign a default user_id from the Fund entity to act as the initial "creator".
  def setup_params(ctx, entity:, portco:, as_of:, period:, **)
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
    params[:portfolio_company].notification_users(model).each do |user|
      KpiReportNotifier.with(record: model, entity_id: params[:entity].id).deliver_later(user)
    end

    Rails.logger.info "Created KPI Report shell and triggered notifications for #{params[:portfolio_company].investor_name} in #{params[:entity].name}"
    true
  end
end
