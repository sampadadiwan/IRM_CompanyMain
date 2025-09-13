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
    xirr_val = portfolio_scenario.calculations[:xirr]
    return true if xirr_val.blank? # Skip if no IRR value

    ratio = FundRatio.find_or_initialize_by(
      owner: portfolio_scenario.fund,
      portfolio_scenario: portfolio_scenario,
      name: "IRR",
      fund: portfolio_scenario.fund,
      entity: portfolio_scenario.entity
    )

    ratio.value = xirr_val
    ratio.display_value = "#{xirr_val} %"
    if ratio.save
      ctx[:irr_ratio] = ratio
    else
      ctx[:errors] ||= []
      ctx[:errors] << "IRR: #{ratio.errors.full_messages.join(', ')}"
      false
    end
  end

  # Attempts to save the MOIC ratio for the portfolio scenario.
  # Sets ctx[:moic_ratio] if successful, or ctx[:errors] if failed.
  def save_fund_moic(ctx, portfolio_scenario:, **)
    moic_val = portfolio_scenario.calculations[:moic]
    return true if moic_val.blank? # Skip if no MOIC value

    ratio = FundRatio.find_or_initialize_by(
      owner: portfolio_scenario.fund,
      portfolio_scenario: portfolio_scenario,
      name: "MOIC",
      fund: portfolio_scenario.fund,
      entity: portfolio_scenario.entity
    )

    ratio.value = moic_val
    ratio.display_value = "#{moic_val} x"
    if ratio.save
      ctx[:moic_ratio] = ratio
    else
      ctx[:errors] ||= []
      ctx[:errors] << "MOIC: #{ratio.errors.full_messages.join(', ')}"
      false
    end
  end

  def save_portfolio_company_ratios(ctx, portfolio_scenario:, **)
    portfolio_company_data = JSON.parse(portfolio_scenario.calculations[:portfolio_company_metrics] || "[]", symbolize_names: true)

    portfolio_company_data.each do |company_id, company_data|
      irr_value = company_data[:xirr]
      moic_value = company_data[:moic]

      [["IRR", irr_value], ["MOIC", moic_value]].each do |name, value|
        ratio = FundRatio.find_or_initialize_by(
          owner_type: "Investor",
          owner_id: company_id.to_s,
          portfolio_scenario: portfolio_scenario,
          name: name,
          fund: portfolio_scenario.fund,
          entity: portfolio_scenario.entity
        )

        ratio.value = value

        display_value = if name == "MOIC"
                          "#{value} x"
                        else
                          "#{value} %"
                        end
        ratio.display_value = display_value

        unless ratio.save
          ctx[:errors] ||= []
          ctx[:errors] << "Company ##{company_data[:name]} - #{company_data[:name]}: #{ratio.errors.full_messages.join(', ')}"
        end
      end
    end
  end

  # Handles errors by ending the operation with failure.
  def handle_errors(_ctx, **)
    # No operation needed, just end with ctx[:errors]
    false
  end
end
