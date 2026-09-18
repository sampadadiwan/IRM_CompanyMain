# frozen_string_literal: true

# Re-converts all FX-converted KPIs for a portfolio company using current
# exchange rates. Triggered manually by the FM from the KPI grid view when
# rates were corrected or added after the original upload.
class KpiCurrencyRecomputeJob < ApplicationJob
  queue_as :default

  # @param portfolio_company_id [Integer] the portfolio company whose KPIs to reconvert
  # @param user_id [Integer, nil] the user to notify on completion
  def perform(portfolio_company_id, user_id: nil)
    portfolio_company = Investor.find(portfolio_company_id)
    converter = KpiFxConverter.new(portfolio_company)

    unless converter.conversion_needed?
      send_notification("No FX conversion needed — KPI currency matches fund currency.", user_id, :info)
      return
    end

    recomputed = 0
    missing_rates = []

    kpis_to_reconvert(portfolio_company).find_each do |kpi|
      mapping = kpi.investor_kpi_mapping
      kpi_report = kpi.kpi_report
      next unless mapping && kpi_report

      new_rate = converter.resolve_fx_rate(mapping, kpi_report)

      if new_rate
        kpi.update(
          value: kpi.original_value * new_rate,
          display_value: kpi.original_value * new_rate,
          fx_rate_used: new_rate
        )
        recomputed += 1
      else
        missing_rates << "#{kpi.name} (#{kpi_report.as_of})"
      end
    end

    message = "FX recompute complete for #{portfolio_company.investor_name}: #{recomputed} KPIs updated."
    message += " Missing rates for: #{missing_rates.first(10).join(', ')}." if missing_rates.any?

    level = missing_rates.any? ? :warning : :success
    send_notification(message, user_id, level)
  end

  private

  # @param portfolio_company [Investor] the portfolio company
  # @return [ActiveRecord::Relation] KPIs that were FX-converted at upload time
  def kpis_to_reconvert(portfolio_company)
    Kpi.where(portfolio_company_id: portfolio_company.id)
       .where.not(original_value: nil)
       .includes(:investor_kpi_mapping, :kpi_report)
  end
end
