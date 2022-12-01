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
        equity_investments = funding_round.investments.equity
        preferred_investments = funding_round.investments.preferred
        esop_investments = funding_round.investments.options_or_esop
        update_investments(equity_investments, preferred_investments, esop_investments)
      end
    else
      # We have to compute the percentage holding for the entire startups investments
      equity_investments = entity.investments.equity
      preferred_investments = entity.investments.preferred
      esop_investments = entity.investments.options_or_esop
      update_investments(equity_investments, preferred_investments, esop_investments)
    end
  end

  def update_investments(equity_investments, preferred_investments, esop_investments)
    equity_quantity = equity_investments.sum(:quantity)
    preferred_quantity = preferred_investments.sum(:preferred_converted_qty)
    esop_quantity = esop_investments.sum(:quantity)

    total_equity = equity_quantity + preferred_quantity
    total_quantity = equity_quantity + preferred_quantity + esop_quantity

    logger.debug "total_equity = #{total_equity}, total_quantity = #{total_quantity} "

    equity_investments.update_all(
      "percentage_holding = quantity * 100.0 / #{total_equity},
         diluted_percentage = quantity * 100.0 / (#{total_quantity})"
    )

    preferred_investments.update_all(
      "percentage_holding = preferred_converted_qty * 100.0 / #{total_equity},
         diluted_percentage = preferred_converted_qty * 100.0 / (#{total_quantity})"
    )

    esop_investments.update_all(
      "percentage_holding = 0,
       diluted_percentage = quantity * 100.0 / (#{total_quantity})"
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
    # Note that for preferred we always use the preferred_converted_qty and not the quantity
    preferred_converted_qty = agg_investments.sum(:preferred_converted_qty)
    options = agg_investments.sum(:options)
    units = agg_investments.sum(:units)

    eq = (equity + preferred_converted_qty + units).positive? ? (equity + preferred_converted_qty + units) : 1
    eq_op = (equity + preferred_converted_qty + units + options).positive? ? (equity + preferred_converted_qty + units + options) : 1

    agg_investments.update_all("percentage = 100*(equity+preferred_converted_qty+units)/#{eq},
                    full_diluted_percentage = 100*(equity+preferred_converted_qty+units+options)/#{eq_op}")
  end
end
