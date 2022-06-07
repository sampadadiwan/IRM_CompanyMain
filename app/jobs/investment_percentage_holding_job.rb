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
    equity_investments = entity.investments.equity_or_pref
    esop_investments = entity.investments.options_or_esop
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
    all = entity.aggregate_investments
    equity = all.sum(:equity)
    preferred = all.sum(:preferred)
    options = all.sum(:options)

    eq = (equity + preferred).positive? ? (equity + preferred) : 1
    eq_op = (equity + preferred + options).positive? ? (equity + preferred + options) : 1

    all.update_all("percentage = 100*(equity+preferred)/#{eq},
                    full_diluted_percentage = 100*(equity+preferred+options)/#{eq_op}")
  end
end
