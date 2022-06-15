class VestedJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    # We need to check for vesting only in pools where excercise is not complete
    OptionPool.where("excercised_quantity < allocated_quantity").each do |pool|
      pool.holdings.not_investors.find_each(batch_size: 500) do |holding|
        unless holding.manual_vesting
          vested_quantity = holding.compute_vested_quantity
          holding.update(vested_quantity:, audit_comment: "Vested quantity updated") if holding.vested_quantity != vested_quantity
        end

        LapseHolding.call(holding:)
      end

      pool.save
    end
  end
end
