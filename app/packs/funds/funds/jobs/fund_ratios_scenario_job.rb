# Computes cross-fund or cross-portfolio ratios and persists them as FundRatio rows.
# Every run creates (or reuses) one FundRatioRun record that stores the exact parameters
# used (which funds, companies, tags, sectors), so results are fully auditable.
# FundRatio rows reference the run via the polymorphic computation_context association.
#
# Design rationale: docs/features/fund_ratio_run.md
class FundRatiosScenarioJob < ApplicationJob
  include Rails.application.routes.url_helpers
  include ApplicationHelper

  queue_as :low
  sidekiq_options retry: 1

  # fund_id                     — anchor fund; stored on FundRatioRun for document folder
  #                               resolution and policy scoping. Does NOT limit calculation data.
  # fund_ids                    — source funds whose data feeds cross-fund calculations.
  # portfolio_company_ids       — explicit company IDs for cross-portfolio (additive with tags/sectors).
  # portfolio_companies_tags    — tag filter; resolves to companies and unions with IDs/sectors.
  # portfolio_companies_sectors — sector filter; resolves to companies and unions with IDs/tags.
  # type                        — "cross-fund" or "cross-portfolio"
  # suppress_notification: true skips the per-run success alert so a batch caller
  # can send one consolidated notification after all runs complete.
  def perform(fund_id, end_date, user_id, fund_ids: nil, portfolio_company_ids: nil, portfolio_companies_tags: nil, portfolio_companies_sectors: nil, currency: nil, type: "cross-fund", suppress_notification: false, template_id: nil)
    setup(fund_id, end_date, user_id, fund_ids:, portfolio_company_ids:, portfolio_companies_tags:, portfolio_companies_sectors:, currency:)
    # find_or_initialize_by: re-running the same inputs on the same date reuses the
    # existing run record (unique index on entity + end_date + name prevents duplicates).
    @run = FundRatioRun.find_or_initialize_by(
      entity: @user.entity,
      end_date: @end_date,
      name: FundRatioRun.fingerprint(
        fund_ids: Array(@fund_ids),
        portfolio_company_ids: Array(@portfolio_company_ids),
        tags: @portfolio_companies_tags,
        sectors: Array(@portfolio_companies_sectors)
      )
    )
    @run.assign_attributes(
      anchor_fund: @fund,
      user: @user,
      run_type: type,
      currency: @currency,
      fund_ids: Array(@fund_ids),
      portfolio_company_ids: Array(@portfolio_company_ids),
      portfolio_companies_tags: @portfolio_companies_tags,
      sectors: Array(@portfolio_companies_sectors),
      fund_ratio_run_template_id: template_id
    )
    begin
      @run.save!
    rescue ActiveRecord::RecordNotUnique
      # Two concurrent jobs with identical inputs hit the unique index simultaneously.
      # The other job won the race — reuse its persisted run record.
      @run = FundRatioRun.find_by!(
        entity: @user.entity,
        end_date: @end_date,
        name: @run.name
      )
    end

    Chewy.strategy(:sidekiq) do
      if type == "cross-fund"
        calc_fund_ratios
      elsif type == "cross-portfolio"
        calc_portfolio_company_ratios
      else
        raise ArgumentError, "Invalid type specified: #{type}"
      end

      # Notification links let the user jump straight to the generated ratios.
      # When a run exists, cross-fund ratios have fund_id nil so we filter by
      # computation_context via ransack — passing fund_id would return nothing.
      # Without a run, ratios are fund-scoped so fund_id is used as before.
      badge_class = 'mb-1 badge bg-primary-subtle text-primary'
      h = ActionController::Base.helpers
      links_html = if @run
                     run_q = ransack_query_params_multiple([
                                                             [:computation_context_id, :eq, @run.id],
                                                             [:computation_context_type, :eq, "FundRatioRun"],
                                                             [:end_date,                 :eq, @run.end_date]
                                                           ])
                     [
                       h.link_to('View Generated Ratios',
                                 fund_ratios_path(filter: true, q: run_q),
                                 class: badge_class, target: '_blank', rel: 'noopener'),
                       h.link_to('View All Ratios',
                                 fund_ratios_path(filter: true),
                                 class: badge_class, target: '_blank', rel: 'noopener')
                     ]
                   else
                     [
                       h.link_to('View Generated Ratios',
                                 fund_ratios_path(fund_id: fund_id, filter: true,
                                                  q: ransack_query_params_multiple([[:end_date, :eq, @end_date]])),
                                 class: badge_class, target: '_blank', rel: 'noopener'),
                       h.link_to('View All Ratios',
                                 fund_ratios_path(fund_id: fund_id, filter: true),
                                 class: badge_class, target: '_blank', rel: 'noopener')
                     ]
                   end.join

      notify("#{@run.run_type.humanize} ratio calculations are now complete.<br> #{links_html}", user_id) unless suppress_notification
    rescue StandardError => e
      notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
      raise e
    end

    @run # return run so batch callers can collect it for a consolidated notification
  end

  def setup(fund_id, end_date, user_id, fund_ids: nil, portfolio_company_ids: nil, portfolio_companies_tags: nil, portfolio_companies_sectors: nil, currency: nil)
    @fund_id  = fund_id
    @fund     = Fund.find_by(id: fund_id) # anchor fund — optional, document storage only
    @end_date = end_date

    # @funds is the ActiveRecord relation used in calculations; @fund_ids is stored on
    # FundRatioRun for auditing. Both can be nil for cross-portfolio runs.
    # Coerce to integers so the JSON column stores numeric values (required for the
    # CAST(fund_ids AS UNSIGNED ARRAY) multi-valued index used by MEMBER OF queries).
    @fund_ids = Array(fund_ids).map(&:to_i).reject(&:zero?).presence
    @funds    = Fund.where(id: @fund_ids) if @fund_ids.present?
    # Raw inputs stored on FundRatioRun for auditing and fingerprinting.
    # Resolution (IDs ∪ tags ∪ sectors) happens via @run.resolved_portfolio_companies.
    @portfolio_company_ids       = Array(portfolio_company_ids).map(&:to_i).reject(&:zero?).presence
    @portfolio_companies_tags    = portfolio_companies_tags
    @portfolio_companies_sectors = Array(portfolio_companies_sectors).compact_blank

    @user     = User.find(user_id)
    @currency = currency || @user.entity.currency
  end

  def calc_fund_ratios
    # Owner must be a Fund so the portfolio dashboard widget (which filters
    # owner_type: ["Fund"]) can find these ratios.
    # Fall back to the first source fund if no anchor fund was set.
    owner = @fund || nil
    # Idempotent: wipe only the ratios that belong to this specific run before recomputing,
    # so other runs with different fingerprints on the same date are not affected.
    FundRatio.where(computation_context: @run).delete_all

    calc = FundRatioMultiFundCalcs.new(@run.name, @end_date, @user.entity, funds: @funds, currency: @currency)

    # computation_context replaces fund_ratio_run; scenario is derived from the run's name
    # by FundRatio#set_scenario_if_missing so we do not need to pass it explicitly.
    # latest: true is set directly — update_latest scopes by fund_id which is nil for
    # cross-fund runs; the delete_all above ensures idempotency so no duplicates arise.
    shared = { computation_context: @run, owner:, entity_id: @user.entity_id, end_date: @end_date, latest: true }

    xirr, cash_flows = calc.xirr(return_cash_flows: false)
    fr = FundRatio.create!(**shared, name: "XIRR", value: xirr, display_value: "#{xirr} %")
    fr.create_cashflow_document(cash_flows, @user.id) if cash_flows.present?

    moic, = calc.moic
    FundRatio.create!(**shared, name: "MOIC", value: moic, display_value: "#{moic} x")

    value = calc.rvpi
    FundRatio.create!(**shared, name: "RVPI", value:, display_value: value ? "#{value.round(2)}x" : nil)

    value = calc.dpi
    FundRatio.create!(**shared, name: "DPI", value:, display_value: value ? "#{value.round(2)}x" : nil)

    value = calc.tvpi
    FundRatio.create!(**shared, name: "TVPI", value:, display_value: value ? "#{value.round(2)}x" : nil)

    value = calc.portfolio_value_to_cost
    FundRatio.create!(**shared, name: "Portfolio Value to Cost", value:, display_value: value ? "#{value.round(2)}x" : nil)

    value = calc.paid_in_to_committed_capital
    FundRatio.create!(**shared, name: "Paid In to Committed Capital", value:, display_value: value ? "#{value.round(2)}x" : nil)

    value = calc.gross_portfolio_irr
    FundRatio.create!(**shared, name: "Gross Portfolio IRR", value:, display_value: "#{value} %")
  end

  def calc_portfolio_company_ratios
    FundRatio.where(computation_context: @run).delete_all

    calc = FundRatioMultiFundCalcs.new(
      @run.name, @end_date, @user.entity,
      funds: @funds,
      portfolio_companies: @run.resolved_portfolio_companies,
      currency: @currency
    )

    # entity_id falls back to @user.entity_id when no anchor fund was set.
    shared = { computation_context: @run, entity_id: @fund&.entity_id || @user.entity_id, end_date: @end_date, latest: true }

    # Aggregate Gross Portfolio IRR stored with Fund owner so aggregate section can show it.
    aggregate_owner = @fund || @funds&.first
    value = calc.gross_portfolio_irr
    FundRatio.create!(**shared, owner: aggregate_owner, name: "Gross Portfolio IRR", value:, display_value: "#{value} %")

    calc.portfolio_company_irr(return_cash_flows: false).each do |portfolio_company_id, values|
      fr = FundRatio.create!(**shared, owner_id: portfolio_company_id, owner_type: "Investor",
                                       name: "IRR", value: values[:xirr], display_value: "#{values[:xirr]} %")
      fr.create_cashflow_document(values[:cash_flows], @user.id) if values[:cash_flows].present?
    end

    calc.portfolio_company_metrics.each do |portfolio_company_id, values|
      FundRatio.create!(**shared, owner_id: portfolio_company_id, owner_type: "Investor",
                                  name: "Value To Cost", value: values[:value_to_cost], display_value: "#{values[:value_to_cost]&.round(2)} x")
      FundRatio.create!(**shared, owner_id: portfolio_company_id, owner_type: "Investor",
                                  name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
    end
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
