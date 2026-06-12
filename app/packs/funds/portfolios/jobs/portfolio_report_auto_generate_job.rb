# Run daily (via Sidekiq-cron or a cron-triggered POST).
# For each PortfolioReportTemplate with auto_generate_enabled=true, checks whether
# today matches the configured frequency/day and, if so, queues one draft per
# portfolio company that has KPI mappings for the owning entity.
class PortfolioReportAutoGenerateJob < ApplicationJob
  queue_as :low

  def perform
    today = Time.zone.today

    PortfolioReportTemplate
      .where(auto_generate_enabled: true)
      .includes(portfolio_report: :entity)
      .find_each do |template|
        next unless due?(template, today)

        entity  = template.portfolio_report.entity
        report  = template.portfolio_report

        # Find all portfolio companies for this entity
        portcos = Investor.where(entity: entity, category: "Portfolio Company")
        portcos.each do |portco|
          kpi_ids = portco.investor_kpi_mappings.show_in_report.pluck(:id)

          draft = PortfolioReportDraft.create!(
            portfolio_company: portco,
            portfolio_report: report,
            portfolio_report_template: template,
            user: entity.users.with_role(:company_admin).first || entity.users.first,
            start_date: start_date_for(template, today),
            end_date: today.end_of_month,
            kpi_period_type: "Monthly",
            kpi_tag: "Actual",
            n_periods: template.kpi_config[:n_periods] || 6,
            selected_kpi_mapping_ids: kpi_ids,
            status: :configuring
          )
          PortfolioReportDraftJob.perform_later(draft.id)

          Rails.logger.info { "[AutoGenerate] Queued draft #{draft.id} for #{portco} / #{template.name}" }
        end

        template.update_column(:auto_generate_last_run_at, Time.current)
      end
  end

  private

  # Returns true if this template is due to run today.
  def due?(template, today)
    day = template.auto_generate_day.to_i.clamp(1, 28)
    return false unless today.day == day

    case template.auto_generate_frequency
    when "monthly"   then true
    when "quarterly" then [1, 4, 7, 10].include?(today.month)
    else false
    end
  end

  # Compute a sensible start_date relative to today and the frequency.
  def start_date_for(template, today)
    case template.auto_generate_frequency
    when "quarterly" then (today - 3.months).beginning_of_month
    else                  (today - 1.month).beginning_of_month
    end
  end
end
