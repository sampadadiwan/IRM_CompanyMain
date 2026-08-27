# frozen_string_literal: true

# Builds a KPI workbook template for a portco's KPI report — the file we would most like them to
# send back (docs/technical/kpi_portco_upload_validation_review.md §3.4 P):
#
#   Row 1  KPI | Unit | <previous period> | <previous period> | <requested period>
#   Rows   one per non-computed InvestorKpiMapping, in the fund's configured order
#
# Period labels are written in a form KpiDateUtils parses back to exactly the shell's as_of/period,
# honouring the entity's fiscal-year start (month_offset_for_fy), so the requested-period check
# passes without guesswork. The "Unit" column carries the mapping's denomination as text; it sits
# left of the first date column, so the importer treats it as a label column and ignores it.
#
# Usage:
#   result = KpiTemplateGenerate.call(kpi_report: report)
#   send_data result[:xlsx], filename: result[:filename]
class KpiTemplateGenerate < Trailblazer::Operation
  step :load_mappings
  step :build_periods
  step :build_workbook

  # How many periods before the requested one to include (gives the portco a place to correct last time)
  PREVIOUS_PERIODS = 2

  def load_mappings(ctx, kpi_report:, **)
    portco = kpi_report.portfolio_company
    ctx[:portco] = portco
    ctx[:mappings] = portco.present? ? portco.investor_kpi_mappings.not_compute.to_a : []
    ctx[:fy_start_month] = fiscal_year_start_month(kpi_report, portco)
    true
  end

  # Labels for [prev-2, prev-1, requested], newest last, each parseable by KpiDateUtils.
  def build_periods(ctx, kpi_report:, **)
    as_of = kpi_report.as_of || Time.zone.today.end_of_month
    period = kpi_report.period.presence || 'Month'
    fy_start = ctx[:fy_start_month]
    dates = (0..PREVIOUS_PERIODS).map { |i| shift_period(as_of, period, -(PREVIOUS_PERIODS - i)) }
    ctx[:period_labels] = dates.map { |d| period_label(d, period, fy_start) }
    true
  end

  def build_workbook(ctx, kpi_report:, mappings:, period_labels:, portco:, **)
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "KPIs") do |ws|
      bold = ws.styles.add_style(b: true)
      ws.add_row ["KPI", "Unit", *period_labels], style: bold
      mappings.each do |m|
        ws.add_row [m.reported_kpi_name, unit_label(m)]
      end
      ws.column_widths 40, 14, *([16] * period_labels.size)
    end
    ctx[:xlsx] = package.to_stream.read
    safe_name = (portco&.investor_name || 'kpis').gsub(/[^\w-]+/, '_')
    ctx[:filename] = "KPI_template_#{safe_name}_#{kpi_report.as_of || Time.zone.today}.xlsx"
    true
  end

  private

  def fiscal_year_start_month(kpi_report, portco)
    KpiDateUtils.resolve_fiscal_year_start_month(portco, kpi_report.entity_id)
  end

  # Moves an end-of-period date by n periods (negative = earlier), staying on period ends.
  def shift_period(as_of, period, n)
    months = case period
             when 'Quarter' then 3
             when 'Half Year' then 6
             when 'Year' then 12
             else 1 # Month, YTD
             end
    (as_of + (n * months).months).end_of_month
  end

  # A label KpiDateUtils.parse_period reads back to `date` with detect_period_type == period.
  def period_label(date, period, fy_start)
    case period
    when 'Quarter'
      # "Apr-Jun 2026" → end_of_quarter(2026, 4) = 30-Jun-2026, type Quarter
      start = date.beginning_of_month - 2.months
      "#{start.strftime('%b')}-#{date.strftime('%b')} #{date.year}"
    when 'Half Year'
      # Calendar halves are unambiguous ("H1 2026"); fiscal halves use the FY label ("H1 FY26")
      if fy_start == 1 || date.month == 6 || date.month == 12
        "H#{date.month <= 6 ? 1 : 2} #{date.year}"
      else
        fy_end_year = fiscal_year_end_year(date, fy_start)
        half = KpiDateUtils.fiscal_year_end(fy_end_year, fy_start) == date ? 2 : 1
        "H#{half} FY#{fy_end_year % 100}"
      end
    when 'Year'
      # Calendar year → "CY2026"; fiscal year → "FY26" (named by the year it ends in)
      fy_start == 1 ? "CY#{date.year}" : "FY#{fiscal_year_end_year(date, fy_start) % 100}"
    when 'YTD'
      "YTD #{date.strftime('%b %Y')}"
    else
      date.strftime('%b %Y')
    end
  end

  # The calendar year in which the fiscal year containing `date` ends.
  def fiscal_year_end_year(date, fy_start)
    date.month >= fy_start ? date.year + 1 : date.year
  end

  def unit_label(mapping)
    return "% (e.g. 42% or 0.42)" if mapping.data_type == 'percentage'

    mapping.denomination.presence&.humanize || (mapping.data_type == 'money' ? 'absolute' : '')
  end
end
