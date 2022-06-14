class AllocationJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id)
    Chewy.strategy(:sidekiq) do
      secondary_sale = SecondarySale.find(secondary_sale_id)
      secondary_sale.allocation_status = "InProgress"
      secondary_sale.save

      begin
        init(secondary_sale)
        update_offers(secondary_sale)
        update_sale(secondary_sale)
        secondary_sale.allocation_status = "Completed"
      rescue StandardError => e
        ExceptionNotifier.notify_exception(e)
        logger.error "Error: #{e.message}"
        logger.error e.backtrace.join("\n")
        secondary_sale.allocation_status = "Error"
      end

      secondary_sale.save
    end
  end

  def init(secondary_sale)
    clean_up(secondary_sale)

    total_offered_quantity = secondary_sale.offers.approved.sum(:quantity)
    total_interest_quantity = secondary_sale.interests.eligible(secondary_sale).sum(:quantity)

    secondary_sale.allocation_percentage = total_offered_quantity.positive? ? (total_interest_quantity * 1.0 / total_offered_quantity).round(4) : 0
    Rails.logger.debug do
      "total_offered_quantity = #{total_offered_quantity},
                  total_interest_quantity = #{total_interest_quantity},
                  secondary_sale.allocation_percentage: #{secondary_sale.allocation_percentage}"
    end
  end

  def clean_up(secondary_sale)
    # Clean everythinteger
    secondary_sale.interests.update_all("allocation_percentage = 0.00,
      allocation_quantity = 0,
      final_price = #{secondary_sale.final_price},
      allocation_amount_cents = 0")
    secondary_sale.offers.update_all("allocation_percentage = 0,
      allocation_quantity = 0,
      final_price = #{secondary_sale.final_price},
      allocation_amount_cents = 0")
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

  def update_sale(secondary_sale)
    # Now compute the actual allocations and update it in the sale
    offers = secondary_sale.offers.approved
    offer_allocation_quantity = offers.sum(:allocation_quantity)
    offer_total_quantity = offers.sum(:quantity)
    Rails.logger.debug { "offer_allocation_quantity: #{offer_allocation_quantity}" }

    interests = secondary_sale.interests.eligible(secondary_sale)
    interest_allocation_quantity = interests.sum(:allocation_quantity)
    interest_total_quantity = interests.sum(:quantity)
    Rails.logger.debug { "interest_allocation_quantity: #{interest_allocation_quantity}" }

    final_price_cents = secondary_sale.final_price * 100
    secondary_sale.update(allocation_percentage: secondary_sale.allocation_percentage,
                          total_offered_quantity: offer_total_quantity,
                          total_offered_amount_cents: offer_total_quantity * final_price_cents,
                          total_interest_quantity: interest_total_quantity,
                          total_interest_amount_cents: interest_total_quantity * final_price_cents,
                          offer_allocation_quantity:,
                          allocation_offer_amount_cents: offer_allocation_quantity * final_price_cents,
                          interest_allocation_quantity:,
                          allocation_interest_amount_cents: interest_allocation_quantity * final_price_cents)
  end

  def match_offers_to_interests(interests, offers)
    Rails.logger.debug { "matching #{offers.count} offers to #{interests.count} interests" }
    # Clear out any prev matches
    offers.update_all(interest_id: nil)

    # Match interests to offers
    interests.each do |interest|
      Rails.logger.debug { "matching interest #{interest.id} to offers" }
      assigned_qty = 0
      # Run thru the unmatched offers
      offers.where(interest_id: nil).each do |offer|
        Rails.logger.debug { "matching interest #{interest.id} to offer #{offer.id}" }

        unassigned_qty = interest.allocation_quantity - assigned_qty
        # Can we assing this offer to this interest?
        if offer.allocation_quantity <= unassigned_qty
          assigned_qty += offer.allocation_quantity
          offer.interest = interest
          offer.save!
          Rails.logger.debug { "Assigned offer #{offer.id} to interest #{interest.id}" }
        else
          break
        end
      end

      Rails.logger.debug { "assigned #{assigned_qty} to interest #{interest.id} with #{interest.allocation_quantity} total" }
    end
  end
end
