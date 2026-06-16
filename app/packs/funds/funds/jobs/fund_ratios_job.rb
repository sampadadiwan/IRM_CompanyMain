require 'csv'

class FundRatiosJob < ApplicationJob
  include Rails.application.routes.url_helpers
  include ApplicationHelper

  queue_as :low
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, capital_commitment_id, end_date, user_id, generate_for_commitments, return_cash_flows: false)
    fund, capital_commitment = _setup_job(fund_id, capital_commitment_id)

    Chewy.strategy(:sidekiq) do
      _calculate_and_touch(fund, capital_commitment, end_date, return_cash_flows, user_id)
      _generate_ratios_for_commitments(fund, end_date, user_id, return_cash_flows) if generate_for_commitments
      fund.update_latest_fund_ratios(end_date)
      _handle_success_notification(fund, end_date, user_id)
    rescue StandardError => e
      _handle_error_notification(e, user_id)
    end
  end

  private

  def _setup_job(fund_id, capital_commitment_id)
    fund = Fund.find(fund_id)
    capital_commitment = capital_commitment_id ? CapitalCommitment.find(capital_commitment_id) : nil
    [fund, capital_commitment]
  end

  def _calculate_and_touch(fund, capital_commitment, end_date, return_cash_flows, user_id)
    calc_fund_ratios(fund, capital_commitment, end_date, return_cash_flows, user_id)
    capital_commitment&.touch
    fund.touch
  end

  def _generate_ratios_for_commitments(fund, end_date, user_id, return_cash_flows)
    fund.capital_commitments.each do |capital_commitment|
      # skip if fund is configured for kyc level data gen and the commitment is marked to skip doc gen (which also implies skipping ratio gen)
      # we assume one of the KYC's commitment will have data gen enabled and will have ratios generated
      next if fund.kyc_level_data_gen? && capital_commitment.skip_doc_gen?

      calc_fund_ratios(fund, capital_commitment, end_date, return_cash_flows, user_id)
      notify("Folio #{capital_commitment.folio_id} calculations are now complete.", user_id)
    rescue StandardError => e
      notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
      raise e
    end
  end

  def _handle_success_notification(fund, end_date, user_id)
    h = ActionController::Base.helpers
    badge_class = 'mb-1 badge bg-primary-subtle text-primary'
    links_html = [
      h.link_to('View Generated Ratios',
                fund_ratios_path(fund_id: fund.id, filter: true,
                                 q: ransack_query_params_multiple([[:end_date, :eq, end_date]])),
                class: badge_class, target: '_blank', rel: 'noopener'),
      h.link_to('View All Ratios',
                fund_ratios_path(fund_id: fund.id, filter: true),
                class: badge_class, target: '_blank', rel: 'noopener')
    ].join
    notify("#{fund.name} ratio calculations are now complete.<br> #{links_html}", user_id)
  end

  def _handle_error_notification(error, user_id)
    notify("Error in fund ratios: #{error.message}", user_id, level: "danger")
    raise error
  end

  def calc_fund_ratios(fund, capital_commitment, end_date, return_cash_flows, user_id)
    _delete_previous_fund_ratios(fund, capital_commitment, end_date)
    # Use factory here to initialize the appropriate calculator based on whether we're calculating for a fund or capital commitment or KYC
    calc, owner = FundRatioCalcInitializer.call(fund, capital_commitment, end_date)

    _create_xirr_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows, user_id)
    _create_moic_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows, user_id)
    _create_rvpi_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_dpi_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_tvpi_ratio(calc, owner, fund, capital_commitment, end_date)

    if fund.has_tracking_currency?
      _create_rvpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: true)
      _create_dpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: true)
      _create_tvpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: true)
    end

    calc_only_fund(calc, fund, capital_commitment, end_date, owner, return_cash_flows:, user_id:) unless capital_commitment
  end

  def _delete_previous_fund_ratios(fund, capital_commitment, end_date)
    FundRatio.where(fund:, capital_commitment:, end_date:).delete_all
  end

  def _create_xirr_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows, user_id)
    xirr, cash_flows = calc.xirr(return_cash_flows:)
    fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR", value: xirr, display_value: "#{xirr} %")
    fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?

    if fund.has_tracking_currency?
      tracking_xirr, cash_flows = calc.xirr(return_cash_flows:, use_tracking_currency: true)
      fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR (#{fund.tracking_currency})", value: tracking_xirr, display_value: "#{tracking_xirr} %")
      fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?
    end
  end

  def _create_moic_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows, user_id)
    # we only compute MOIC for FundPortfolioCalcs, not for others - confirm why
    return unless calc.is_a?(FundPortfolioCalcs)

    moic, cash_flows = calc.moic(return_cash_flows:)
    fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC", value: moic, display_value: "#{moic} x")
    fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?

    if fund.has_tracking_currency?
      tracking_moic, cash_flows = calc.moic(return_cash_flows:, use_tracking_currency: true)
      fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC (#{fund.tracking_currency})", value: tracking_moic, display_value: "#{tracking_moic} x")
      fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?
    end
  end

  def _create_rvpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: false)
    value = calc.rvpi(use_tracking_currency:)
    display_value = value ? "#{value.round(2)}x" : nil
    name = use_tracking_currency ? "RVPI (#{fund.tracking_currency})" : "RVPI"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name:, value:, display_value:)
  end

  def _create_dpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: false)
    value = calc.dpi(use_tracking_currency:)
    display_value = value ? "#{value.round(2)}x" : nil
    name = use_tracking_currency ? "DPI (#{fund.tracking_currency})" : "DPI"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name:, value:, display_value:)
  end

  def _create_tvpi_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: false)
    value = calc.tvpi(use_tracking_currency:)
    display_value = value ? "#{value.round(2)}x" : nil
    name = use_tracking_currency ? "TVPI (#{fund.tracking_currency})" : "TVPI"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name:, value:, display_value:)
  end

  def calc_only_fund(calc, fund, capital_commitment, end_date, owner, return_cash_flows:, user_id:)
    _create_portfolio_value_to_cost_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_paid_in_to_committed_capital_ratio(calc, owner, fund, capital_commitment, end_date)

    if fund.has_tracking_currency?
      _create_portfolio_value_to_cost_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: true)
      _create_paid_in_to_committed_capital_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: true)
    end
    _create_portfolio_company_irr_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    _create_api_irr_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    _create_portfolio_company_moic_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    _create_api_moic_ratios(calc, fund, capital_commitment, end_date, return_cash_flows, user_id)
    _create_gross_portfolio_irr_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
  end

  def _create_portfolio_value_to_cost_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: false)
    value = calc.portfolio_value_to_cost(use_tracking_currency:)
    display_value = value ? "#{value.round(2)}x" : nil
    name = use_tracking_currency ? "Portfolio Value to Cost (#{fund.tracking_currency})" : "Portfolio Value to Cost"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name:, value:, display_value:)
  end

  def _create_paid_in_to_committed_capital_ratio(calc, owner, fund, capital_commitment, end_date, use_tracking_currency: false)
    value = calc.paid_in_to_committed_capital(use_tracking_currency:)
    display_value = value ? "#{value.round(2)}x" : nil
    name = use_tracking_currency ? "Paid In to Committed Capital (#{fund.tracking_currency})" : "Paid In to Committed Capital"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name:, value:, display_value:)
  end

  def _create_portfolio_company_irr_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    calc.portfolio_company_irr(return_cash_flows:).each do |portfolio_company_id, values|
      fr = FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value: values[:xirr], display_value: "#{values[:xirr]} %")
      fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
    end

    if fund.has_tracking_currency?
      calc.portfolio_company_irr_map = {}
      calc.portfolio_company_irr(return_cash_flows:, use_tracking_currency: true).each do |portfolio_company_id, values|
        fr = FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR (#{fund.tracking_currency})", value: values[:xirr], display_value: "#{values[:xirr]} %")
        fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
      end
    end
  end

  def _create_api_irr_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    calc.api_irr(return_cash_flows:).each do |api_id, values|
      value = values[:xirr]
      cash_flows = values[:cash_flows]
      fr = FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value:, display_value: "#{value} %")
      fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?
    end

    if fund.has_tracking_currency?
      calc.api_irr_map = {}
      calc.api_irr(return_cash_flows:, use_tracking_currency: true).each do |api_id, values|
        fr = FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR (#{fund.tracking_currency})", value: values[:xirr], display_value: "#{values[:xirr]} %")
        fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
      end
    end
  end

  def _create_portfolio_company_moic_ratios(calc, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    calc.portfolio_company_metrics(return_cash_flows:).each do |portfolio_company_id, values|
      fr = FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
      fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
    end

    if fund.has_tracking_currency?
      calc.portfolio_company_metrics_map = {}
      calc.portfolio_company_metrics(return_cash_flows:, use_tracking_currency: true).each do |portfolio_company_id, values|
        fr = FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC (#{fund.tracking_currency})", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
        fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
      end
    end
    # TODO: do we need moic for tracking currency?
  end

  def _create_api_moic_ratios(calc, fund, capital_commitment, end_date, return_cash_flows, user_id)
    calc.api_cost_to_value(return_cash_flows:).each do |api_id, values|
      fr = FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
      fr.create_cashflow_document(values[:cash_flows], user_id) if return_cash_flows && values[:cash_flows].present?
    end
  end

  def _create_gross_portfolio_irr_ratios(calc, owner, fund, capital_commitment, end_date, return_cash_flows:, user_id:)
    result = calc.gross_portfolio_irr(return_cash_flows:)
    xirr_value = result[:xirr]
    cash_flows = result[:cash_flows]
    display_value = "#{xirr_value} %"
    fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR", value: xirr_value, display_value:)
    fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?

    if fund.has_tracking_currency?
      result = calc.gross_portfolio_irr(return_cash_flows:, use_tracking_currency: true)
      xirr_value = result[:xirr]
      cash_flows = result[:cash_flows]
      display_value = "#{xirr_value} %"
      fr = FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR (#{fund.tracking_currency})", value: xirr_value, display_value:)
      fr.create_cashflow_document(cash_flows, user_id) if return_cash_flows && cash_flows.present?
    end
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
