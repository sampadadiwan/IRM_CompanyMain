class VestedJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    Chewy.strategy(:sidekiq) do
      # We need to check for vesting only in pools where excercise is not complete
      OptionPool.where("excercised_quantity < allocated_quantity").each do |pool|
        process_pool(pool)
      end
    end
  end

  # rubocop:disable Security/Eval
  def process_pool(pool)
    pool.holdings.not_investors.not_lapsed.find_each(batch_size: 500) do |holding|
      if holding.manual_vesting
        # The formula is entered manually into the DB, users cannot enter it.
        vested_quantity = eval(holding.option_pool.formula)
        audit_comment = "Vested quantity based on formula"
      else
        vested_quantity = holding.compute_vested_quantity
        audit_comment = "Vested quantity based on schedule"
      end
      holding.update(vested_quantity:, audit_comment:) if holding.vested_quantity != vested_quantity

      LapseHolding.call(holding:)
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
