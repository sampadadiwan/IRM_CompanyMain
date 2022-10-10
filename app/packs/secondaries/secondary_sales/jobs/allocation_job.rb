class AllocationJob < AllocationBase
  def perform(secondary_sale_id)
    Chewy.strategy(:sidekiq) do
      secondary_sale = SecondarySale.find(secondary_sale_id)

      unless secondary_sale.lock_allocations

        begin
          init(secondary_sale)
          update_offers(secondary_sale)
          update_sale(secondary_sale)
          secondary_sale.allocation_status = "Completed"
        rescue StandardError => e
          ExceptionNotifier.notify_exception(e)
          logger.error e.backtrace.join("\n")
          secondary_sale.allocation_status = "Error"
        end

        secondary_sale.save

      end
    end
  end

  def get_total_offered_quantity(secondary_sale)
    secondary_sale.offers.approved.sum(:quantity)
  end

  def get_total_offered_allocation_quantity(secondary_sale)
    secondary_sale.offers.approved.sum(:allocation_quantity)
  end

  def update_offers(secondary_sale)
    interests = secondary_sale.interests.eligible(secondary_sale)
    offers = secondary_sale.offers.approved

    if secondary_sale.allocation_percentage <= 1
      interest_percentage = 1
      # We only can allocate  a portion of the offers
      offer_percentage = (1.0 * secondary_sale.allocation_percentage).round(6)
    else
      offer_percentage = 1
      # We only can allocate a portion of the interests
      interest_percentage = (1.0 / secondary_sale.allocation_percentage).round(6)
    end

    Rails.logger.debug { "allocating #{interest_percentage}% of interests and #{offer_percentage} % of offers" }

    # We have more interests #{100.00 * interest_percentage},
    interests.update_all("allocation_percentage = #{100.00 * interest_percentage},
      allocation_quantity = ceil(quantity * #{interest_percentage}),
      final_price = #{secondary_sale.final_price},
      allocation_amount_cents = (ceil(quantity * #{interest_percentage}) * #{secondary_sale.final_price * 100})")

    offers.update_all(" allocation_percentage = #{100.00 * offer_percentage},
      allocation_quantity = ceil(quantity * #{offer_percentage}),
      final_price = #{secondary_sale.final_price},
      allocation_amount_cents = (ceil(quantity * #{offer_percentage}) * #{secondary_sale.final_price * 100})")

    # Sometimes we overallocate. so we need to adjust
    # update_delta(interests, offers)

    # Now match the offers to interests
    match_offers_to_interests(interests, offers)
  end

  def update_delta(interests, offers)
    delta = interests.sum(:allocation_quantity) - offers.sum(:allocation_quantity)
    if delta.positive?
      # We over allocated, we cant allocate more to buyers than what sellers are selling
      last_interest = interests.last
      last_interest.update(allocation_quantity: last_interest.allocation_quantity - delta)
    end
  end
end
