# An unsaved statement set for previewing: the mapping screen renders the fund's statements for any
# period straight from the calculator, without running anything or creating a record. Quacks like
# FinancialStatement for FinancialStatementPresenter.
# Worked examples H2, H8 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementPreview
  attr_reader :fund, :start_date, :end_date, :result

  def initialize(fund:, start_date:, end_date:)
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @result = FinancialStatementCalculator.call(fund:, start_date:, end_date:, setting:)
  end

  def id
    nil
  end

  def setting
    @setting ||= FinancialStatementSetting.find_by(fund_id: fund.id) || FinancialStatementSetup.default_setting(fund)
  end

  def fy_start
    setting.fiscal_year_start(end_date)
  end

  delegate :figures, to: :result

  def period_label
    "#{I18n.l(start_date)} – #{I18n.l(end_date)}"
  end

  def statements
    @statements ||= FinancialStatementPresenter.new(self).statements
  end
end
