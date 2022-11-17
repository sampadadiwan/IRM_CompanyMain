class AllocationBase < ApplicationJob
  queue_as :default

  def init(secondary_sale)
    secondary_sale.allocation_status = "InProgress"
    secondary_sale.cmf_allocation_percentage = {}

    secondary_sale.save

    clean_up(secondary_sale)

    # total_offered_quantity = get_total_offered_quantity(secondary_sale)
    # total_interest_quantity = secondary_sale.interests.eligible(secondary_sale).sum(:quantity)

    # secondary_sale.allocation_percentage = total_offered_quantity.positive? ? (total_interest_quantity * 1.0 / total_offered_quantity).round(4) : 0
    # Rails.logger.debug do
    #   "total_offered_quantity = #{total_offered_quantity},
    #         total_interest_quantity = #{total_interest_quantity},
    #         secondary_sale.allocation_percentage: #{secondary_sale.allocation_percentage}"
    # end
  end

  def clean_up(secondary_sale)
    # Clean everything set by this job
    secondary_sale.interests.update_all("allocation_percentage = 0.00,
            allocation_quantity = 0,
            final_price = #{secondary_sale.final_price},
            allocation_amount_cents = 0,
            offer_quantity = 0")
    secondary_sale.offers.update_all("allocation_percentage = 0,
            allocation_quantity = 0,
            final_price = #{secondary_sale.final_price},
            allocation_amount_cents = 0,
            interest_id = null")
  end

  def get_total_offered_quantity(secondary_sale)
    secondary_sale.offers.approved.sum(:quantity)
  end

  def get_total_offered_allocation_quantity(secondary_sale)
    secondary_sale.offers.approved.sum(:allocation_quantity)
  end

  def update_sale(secondary_sale)
    # Now compute the actual allocations and update it in the sale
    offer_allocation_quantity = get_total_offered_allocation_quantity(secondary_sale)
    offer_total_quantity = get_total_offered_quantity(secondary_sale)
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
    interests.order(allocation_quantity: :desc).find_each(batch_size: 100) do |interest|
      Rails.logger.debug { "matching interest #{interest.id} to offers" }
      assigned_qty = 0
      # Run thru the unmatched offers, which are allowed to auto_match
      offers.auto_match.where(interest_id: nil).order(allocation_quantity: :desc).find_each(batch_size: 100) do |offer|
        Rails.logger.debug { "matching interest #{interest.id} to offer #{offer.id}" }

        unassigned_qty = interest.allocation_quantity - assigned_qty
        # Can we assing this offer to this interest?
        if offer.allocation_quantity <= unassigned_qty && offer.allocation_quantity.positive?
          assigned_qty += offer.allocation_quantity
          offer.interest = interest
          offer.save!
          Rails.logger.debug { "Assigned offer #{offer.id} to interest #{interest.id}" }
        else
          # puts "#### offer #{offer.id},  interest.allocation_quantity = #{interest.allocation_quantity}, offer.allocation_quantity = #{offer.allocation_quantity} unassigned_qty = #{unassigned_qty}, assigned_qty = #{assigned_qty}"

          next
        end
      end

      Rails.logger.debug { "assigned #{assigned_qty} to interest #{interest.id} with #{interest.allocation_quantity} total" }
    end
  end
end
