class VestedJob < ApplicationJob
  queue_as :default

  def perform(option_pool_id: nil, user_id: nil)
    Chewy.strategy(:sidekiq) do
      # We need to check for vesting only in pools where excercise is not complete
      if option_pool_id.present?
        process_pool(OptionPool.find(option_pool_id))
      else
        OptionPool.where("excercised_quantity < allocated_quantity").find_each do |pool|
          process_pool(pool)
        end
      end

      UserAlert.new(message: "Vesting Job completed. Please refresh.", user_id:, level: "info").broadcast if user_id
    end
  end

  # rubocop:disable Security/Eval
  def process_pool(pool)
    pool.holdings.approved.not_investors.not_lapsed.find_each(batch_size: 500) do |holding|
      if holding.manual_vesting
        # The formula is entered manually into the DB, users cannot enter it.
        if holding.option_pool.formula.present?
          vested_quantity = eval(holding.option_pool.formula)
          audit_comment = "Vested quantity based on formula"
        else
          Rails.logger.error("Vested quantity not calculated for #{holding.id}. Please enter formula.")
          audit_comment = "Vested quantity not calculated. Please enter formula."
        end
      else
        vested_quantity = holding.compute_vested_quantity
        audit_comment = "Vested quantity based on schedule"
      end
      holding.update(vested_quantity:, audit_comment:) if holding.vested_quantity != vested_quantity

      LapseHolding.wtf?(holding:)
    end

    pool.save
  end
  # rubocop:enable Security/Eval

  def sample_formula
    performance_ranking = holding.properties["performance_ranking"]
    sales_revenue = holding.properties["sales_revenue"]

    if performance_ranking == "Top 10%"
      holding.orig_grant_quantity
    elsif performance_ranking == "Top 25%"
      if sales_revenue > 1_000_000
        holding.orig_grant_quantity * 0.8
      else
        holding.orig_grant_quantity * 0.6
      end
    else
      holding.orig_grant_quantity * 0.4
    end
  end
end
