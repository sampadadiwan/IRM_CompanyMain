# frozen_string_literal: true

# Resolves FX rates and converts KPI values from a portfolio company's
# reporting currency (kpi_currency) to the fund's base currency.
# Extracted from KpiWorkbookReader so the same logic is reusable by
# KpiCurrencyRecomputeJob without depending on the workbook context.
class KpiFxConverter
  # @param portfolio_company [Investor] the portfolio company whose KPIs are being converted
  def initialize(portfolio_company)
    @portfolio_company = portfolio_company
    @kpi_currency = portfolio_company.json_fields&.dig('kpi_currency')
    @fund_currency = portfolio_company.entity.currency
    @entity_id = portfolio_company.entity_id
  end

  # @return [Boolean] true when the portco reports in a different currency than the fund
  def conversion_needed?
    @kpi_currency.present? && @kpi_currency != @fund_currency
  end

  # @return [String, nil] the portfolio company's reporting currency
  attr_reader :kpi_currency

  # @return [String] the fund's base currency
  attr_reader :fund_currency

  # Resolves the FX rate for a KPI based on the mapping's fx_conversion_method.
  # Returns nil if currencies are the same, method is not_applicable, or rate is missing.
  # @param investor_kpi_mapping [InvestorKpiMapping] the mapping with fx_conversion_method
  # @param kpi_report [KpiReport] the report (provides as_of date and period)
  # @return [BigDecimal, nil] the FX rate to multiply by, or nil if no conversion needed
  def resolve_fx_rate(investor_kpi_mapping, kpi_report)
    return nil unless conversion_needed?
    return nil if investor_kpi_mapping.fx_not_applicable?

    if investor_kpi_mapping.fx_report_date?
      ExchangeRate.get_rate(@kpi_currency, @fund_currency, kpi_report.as_of, @entity_id)
    elsif investor_kpi_mapping.fx_average_rate?
      opening_date = period_start_date(kpi_report)
      closing_date = kpi_report.as_of
      opening_rate = ExchangeRate.get_rate(@kpi_currency, @fund_currency, opening_date, @entity_id)
      closing_rate = ExchangeRate.get_rate(@kpi_currency, @fund_currency, closing_date, @entity_id)
      return nil unless opening_rate && closing_rate

      (opening_rate + closing_rate) / 2.0
    end
  end

  # Calculates the period start date for average rate FX conversion.
  # @param kpi_report [KpiReport] the report with as_of and period
  # @return [Date] the opening date of the period
  def period_start_date(kpi_report)
    as_of = kpi_report.as_of
    case kpi_report.period&.downcase
    when 'quarter'
      as_of.beginning_of_quarter
    when 'half year'
      as_of - 6.months + 1.day
    when 'year'
      as_of.beginning_of_year
    when 'ytd'
      @portfolio_company.start_of_financial_year_date(as_of)
    else
      as_of.beginning_of_month
    end
  end
end
