class InvestmentPercentageHoldingJob < ApplicationJob
  queue_as :default

  def perform(entity_id)
    Chewy.strategy(:sidekiq) do
      entity = Entity.find(entity_id)
      if entity.percentage_in_progress

        Rails.logger.debug { "InvestmentPercentageHoldingJob: Started #{entity_id}" }

        begin
          # Ensure that all investments of the investee entity are adjusted for percentage
          update_investment_percentage(entity)
          # Ensure that all aggregate investments of the investee entity are adjusted for percentage
          update_aggregate_percentage(entity) if entity.aggregate_investments.present?
        rescue StandardError => e
          Rails.logger.debug { "InvestmentPercentageHoldingJob: Error #{e.message}" }
        end

        entity.transaction do
          entity.reload
          entity.percentage_in_progress = false
          entity.save
        end

        Rails.logger.debug { "InvestmentPercentageHoldingJob: Completed #{entity_id}" }
      end
    end
  end

  private

  def update_investment_percentage(entity)
    if entity.entity_type == "Investment Fund"
      # We have to compute the percentage holding per fund
      entity.funding_rounds.each do |funding_round|
        equity_investments = funding_round.investments.equity_or_pref
        esop_investments = funding_round.investments.options_or_esop
        update_investments(equity_investments, esop_investments)
      end
    else
      # We have to compute the percentage holding for the entire startups investments
      equity_investments = entity.investments.equity_or_pref
      esop_investments = entity.investments.options_or_esop
      update_investments(equity_investments, esop_investments)
    end
  end

  def update_investments(equity_investments, esop_investments)
    equity_quantity = equity_investments.sum(:quantity)
    esop_quantity = esop_investments.sum(:quantity)

    equity_investments.update_all(
      "percentage_holding = quantity * 100.0 / #{equity_quantity},
         diluted_percentage = quantity * 100.0 / (#{equity_quantity + esop_quantity})"
    )

    esop_investments.update_all(
      "percentage_holding = 0,
       diluted_percentage = quantity * 100.0 / (#{equity_quantity + esop_quantity})"
    )
  end

  def update_aggregate_percentage(entity)
    if entity.entity_type == "Investment Fund"
      entity.funding_rounds.each do |funding_round|
        fund_agg_inv = funding_round.aggregate_investments
        update_aggregate(fund_agg_inv)
      end
    else
      all = entity.aggregate_investments
      update_aggregate(all)
    end
  end

  def update_aggregate(agg_investments)
    equity = agg_investments.sum(:equity)
    preferred = agg_investments.sum(:preferred)
    options = agg_investments.sum(:options)
    units = agg_investments.sum(:units)

    eq = (equity + preferred + units).positive? ? (equity + preferred + units) : 1
    eq_op = (equity + preferred + units + options).positive? ? (equity + preferred + units + options) : 1

    agg_investments.update_all("percentage = 100*(equity+preferred+units)/#{eq},
                    full_diluted_percentage = 100*(equity+preferred+units+options)/#{eq_op}")
  end
end
