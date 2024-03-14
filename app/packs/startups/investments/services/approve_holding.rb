class ApproveHolding < HoldingAction
  step :approve_holding
  step :setup_holding_for_investment
  left :handle_error
  step :notify_holding_approval
  step :generate_option_grant_letter
  step :update_trust_holdings

  def approve_holding(_ctx, holding:, **)
    holding.update(approved: true)
  end

  def setup_holding_for_investment(_ctx, holding:, **)
    if Holding::INVESTMENT_FOR.include?(holding.holding_type)

      holding.investment = Investment.for(holding).first
      holding.funding_round_id = holding.option_pool.funding_round_id if holding.option_pool

      if holding.investment.nil?
        Rails.logger.debug { "Creating investment for #{holding.id}" }
        employee_holdings = holding.holding_type != "Investor"
        investment = Investment.new(investment_type: "#{holding.holding_type} Holdings",
                                    investment_instrument: holding.investment_instrument,
                                    category: holding.holding_type, entity_id: holding.entity.id,
                                    investor_id: holding.investor_id, employee_holdings:,
                                    quantity: 0, price_cents: holding.price_cents,
                                    investment_date: holding.grant_date,
                                    currency: holding.entity.currency, funding_round: holding.funding_round,
                                    notes: "Holdings Investment")

        if SaveInvestment.call(investment:).success?
          holding.investment = investment
        else
          return false
        end
      else
        Rails.logger.debug { "Investment already exists for #{holding.id}" }
      end

      holding.save
    end
  end

  def notify_holding_approval(_ctx, holding:, **)
    holding.notify_approval
    true
  end

  def generate_option_grant_letter(_ctx, holding:, **)
    if holding.investment_instrument == "Options" && holding.user.present?
      EsopLetterJob.perform_later(holding.id)
    else
      Rails.logger.debug { "GenerateOptionGrantLetter: Skipping as holding #{holding.id} not an option" }
    end
  end
end
