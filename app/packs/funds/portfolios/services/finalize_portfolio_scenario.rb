# services/portfolio_scenarios/from_finalized_portfolio_scenario.rb
# Operation to create FundRatio records (IRR and MOIC) from a finalized PortfolioScenario's calculations.
class FinalizePortfolioScenario < Trailblazer::Operation
  step :save_fund_irr
  left :handle_errors, id: :handle_fund_irr_errors, Output(:failure) => End(:failure)
  step :save_fund_moic
  left :handle_errors, id: :handle_fund_moic_errors, Output(:failure) => End(:failure)
  step :save_portfolio_company_ratios
  left :handle_errors, id: :handle_company_ratios_errors, Output(:failure) => End(:failure)

  # Attempts to save the IRR ratio for the portfolio scenario.
  # Sets ctx[:irr_ratio] if successful, or ctx[:errors] if failed.
  def save_fund_irr(ctx, portfolio_scenario:, **)
    xirr_default_val = portfolio_scenario.calculations[:xirr]
    xirr_tracking_val = portfolio_scenario.calculations[:xirr_tracking_currency]
    tracking_currency = portfolio_scenario.calculations[:tracking_currency]
    return true if [xirr_default_val, xirr_tracking_val].compact.blank? # Skip if no IRR value

    ctx[:fund_end_date] ||= portfolio_scenario.scenario_investments.maximum(:transaction_date) || PortfolioInvestment.where(fund_id: portfolio_scenario.fund_id, entity_id: portfolio_scenario.entity_id).maximum(:investment_date)

    [["IRR", xirr_default_val], ["IRR (#{tracking_currency})", xirr_tracking_val]].each do |xirr_name, xirr_val|
      next if xirr_val.blank?

      ratio = FundRatio.find_or_initialize_by(
        owner: portfolio_scenario.fund,
        portfolio_scenario: portfolio_scenario,
        name: xirr_name,
        fund: portfolio_scenario.fund,
        entity: portfolio_scenario.entity
      )

      ratio.value = xirr_val
      ratio.display_value = "#{xirr_val} %"
      # Assign the end_date based on the last transaction date in scenario investments
      ratio.end_date = ctx[:fund_end_date]

      if ratio.save
        ctx[:irr_ratio] = ratio
      else
        ctx[:errors] ||= []
        ctx[:errors] << "#{xirr_name}: #{ratio.errors.full_messages.join(', ')}"
      end
    end
    ctx[:errors].blank?
  end

  # Attempts to save the MOIC ratio for the portfolio scenario.
  # Sets ctx[:moic_ratio] if successful, or ctx[:errors] if failed.
  def save_fund_moic(ctx, portfolio_scenario:, **)
    moic_default_val = portfolio_scenario.calculations[:moic]
    moic_tracking_val = portfolio_scenario.calculations[:moic_tracking_currency]
    tracking_currency = portfolio_scenario.calculations[:tracking_currency]

    return true if [moic_default_val, moic_tracking_val].compact.blank? # Skip if no MOIC value

    ctx[:fund_end_date] ||= portfolio_scenario.scenario_investments.maximum(:transaction_date) || PortfolioInvestment.where(fund_id: portfolio_scenario.fund_id, entity_id: portfolio_scenario.entity_id).maximum(:investment_date)

    [["MOIC", moic_default_val], ["MOIC (#{tracking_currency})", moic_tracking_val]].each do |moic_name, moic_val|
      next if moic_val.blank?

      ratio = FundRatio.find_or_initialize_by(
        owner: portfolio_scenario.fund,
        portfolio_scenario: portfolio_scenario,
        name: moic_name,
        fund: portfolio_scenario.fund,
        entity: portfolio_scenario.entity
      )

      ratio.value = moic_val
      ratio.display_value = "#{moic_val} x"
      # Assign the end_date based on the last transaction date in scenario investments
      ratio.end_date = ctx[:fund_end_date]

      if ratio.save
        ctx[:moic_ratio] = ratio
      else
        ctx[:errors] ||= []
        ctx[:errors] << "#{moic_name}: #{ratio.errors.full_messages.join(', ')}"
      end
    end
    ctx[:errors].blank?
  end

  # rubocop:disable Metrics/MethodLength
  def save_portfolio_company_ratios(ctx, portfolio_scenario:, **)
    # Parse the JSON into a hash keyed by company_id -> metrics hash
    portfolio_company_data = JSON.parse(
      portfolio_scenario.calculations[:portfolio_company_metrics] || "{}",
      symbolize_names: true
    )

    portfolio_company_data.each do |company_id, company_data| # rubocop:disable Metrics/BlockLength
      # company_data ex: { name:, xirr:, xirr_USD:, moic:, moic_USD:, cash_flows: [...] }

      # Collect all metric/currency pairs dynamically, e.g.
      # :xirr        -> ["",    value]   (base currency, no suffix)
      # :xirr_USD    -> ["USD", value]
      # :moic        -> ["",    value]
      # :moic_EUR    -> ["EUR", value]
      metric_currency_pairs = []

      company_id = company_id.to_s
      company_data.each do |key, value|
        next if value.nil?

        # Get the ratios in default and tracking currency
        key_str = key.to_s
        if key_str.start_with?("xirr")
          currency = key_str.split("_", 2)[1] # nil for base
          metric_currency_pairs << ["IRR", currency, value]
        elsif key_str.start_with?("moic")
          currency = key_str.split("_", 2)[1] # nil for base
          metric_currency_pairs << ["MOIC", currency, value]
        end
      end

      #  Assign the end_date based on the last transaction date for the company in the scenario investments, or fallback to the last investment date in PortfolioInvestment if no scenario investments exist for that company
      company_end_date = portfolio_scenario.scenario_investments.where(portfolio_company_id: company_id).maximum(:transaction_date) ||
                         PortfolioInvestment.where(portfolio_company_id: company_id, fund_id: portfolio_scenario.fund_id, entity_id: portfolio_scenario.entity_id).maximum(:investment_date)

      metric_currency_pairs.each do |metric_name, currency, value|
        # Build a readable name including currency if present
        ratio_name = currency.nil? ? metric_name : "#{metric_name} (#{currency})"

        ratio = FundRatio.find_or_initialize_by(
          owner_type: "Investor",
          owner_id: company_id,
          portfolio_scenario: portfolio_scenario,
          name: ratio_name,
          fund: portfolio_scenario.fund,
          entity: portfolio_scenario.entity
        )

        ratio.value = value

        ratio.display_value =
          if metric_name == "MOIC"
            "#{value} x"
          else
            "#{value} %"
          end

        ratio.end_date = company_end_date

        next if ratio.save

        ctx[:errors] ||= []
        # Use company_data[:name] if available; otherwise fallback to company_id
        label = company_data[:name] || company_id
        ctx[:errors] << "Company ##{label}: #{ratio.errors.full_messages.join(', ')}"
      end
    end

    ctx[:errors].blank?
  end
  # rubocop:enable Metrics/MethodLength

  # Handles errors by ending the operation with failure.
  def handle_errors(_ctx, **)
    # No operation needed, just end with ctx[:errors]
    false
  end
end
