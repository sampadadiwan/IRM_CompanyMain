# Settings tab: financial year start and the entries the NAV and partners' capital checks use.
# Worked examples E6, E7, E21 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementSettingsController < ApplicationController
  include FinancialStatementFundContext

  # How far back the Settings suggestions look for NAV / capital entries
  SUGGESTION_WINDOW = 13.months

  before_action :set_setting
  after_action :verify_authorized

  def edit
    # "Use" on a suggestion pre-fills the fields (nothing is saved until Save settings)
    @setting.assign_attributes(params.permit(:nav_entry_type, :nav_entry_name, :capital_entry_type, :capital_entry_name).to_h.compact_blank)
    load_status_and_suggestions
    fund_breadcrumbs("Settings")
  end

  def update
    # New financial year / NAV / capital entries apply to the next preview and generation
    if @setting.update(setting_params)
      redirect_to edit_financial_statement_setting_path(@setting), notice: "Settings saved."
    else
      load_status_and_suggestions
      fund_breadcrumbs("Settings")
      render :edit, status: :unprocessable_content
    end
  end

  private

  # What the chosen entries find today, and candidate entries from the fund's own data, so the user
  # can see whether a setting is right before saving. Grouped / limited queries only.
  def load_status_and_suggestions
    entries = AccountEntry.where(fund_id: @fund.id, deleted_at: nil).where.not(entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE)
    # NAV: the latest fund-level value of the chosen entry
    if @setting.nav_configured?
      nav = entries.where(capital_commitment_id: nil, entry_type: @setting.nav_entry_type, name: @setting.nav_entry_name)
      latest = nav.maximum(:reporting_date)
      @nav_status = latest ? { date: latest, value: nav.where(reporting_date: latest).sum(:amount_cents) } : { missing: true }
    end
    # Capital: how many folios carry the chosen entry, and their latest values added up
    if @setting.capital_configured?
      folios = entries.where.not(capital_commitment_id: nil).where(entry_type: @setting.capital_entry_type, name: @setting.capital_entry_name)
      count = folios.distinct.count(:capital_commitment_id)
      @capital_status = if count.zero?
                          { missing: true }
                        else
                          { folios: count,
                            value: FinancialStatementCalculator.latest_value(AccountEntry, @fund, @setting.capital_entry_type, @setting.capital_entry_name,
                                                                             Time.zone.today, folio: true) }
                        end
    end
    # Suggestions: fund-level entries that look like a NAV, folio-level entries that look like capital.
    # A "%…%" match can't use an index, so only the last 13 months are searched (large-table hygiene,
    # CLAUDE.md) — enough to find the entries the fund writes today
    recent = entries.where(reporting_date: SUGGESTION_WINDOW.ago.to_date..)
    @nav_suggestions = recent.where(capital_commitment_id: nil).where("entry_type LIKE ? OR name LIKE ?", "%NAV%", "%NAV%")
                             .distinct.limit(8).pluck(:entry_type, :name)
    @capital_suggestions = recent.where.not(capital_commitment_id: nil).where("name LIKE ?", "%Capital%")
                                 .distinct.limit(8).pluck(:entry_type, :name)
  end

  def set_setting
    @setting = policy_scope(FinancialStatementSetting).find(params[:id])
    @fund = @setting.fund
    authorize @setting
  end

  def setting_params
    params.expect(financial_statement_setting: %i[fiscal_year_start_month nav_entry_type nav_entry_name capital_entry_type capital_entry_name])
  end
end
