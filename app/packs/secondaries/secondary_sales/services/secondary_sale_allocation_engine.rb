# Terminology Used:
# - Supply-Driven Matching (Seller-Driven): In this approach, sellers (offers) have control,
#   and buyers (interests) are matched to them. The seller sets the terms (price and quantity),
#   and buyers must meet them. This is typical in markets where supply is limited.
#
# - Demand-Driven Matching (Buyer-Driven): In this approach, buyers (interests) have control
#   and select from available offers. Buyers dictate the terms, and sellers compete to meet
#   the buyers' demand. This is typical in competitive seller markets.
#
# - Buyer Advantage: When the buyer gets the most favorable price. In this case, buyers
#   will be matched to the lowest-priced offers.
#
# - Seller Advantage: When the seller gets the most favorable price. In this case, sellers
#   will be matched to the highest-priced interests.

class SecondarySaleAllocationEngine < BaseAllocationEngine
  def initialize(secondary_sale, user_id:, priority: :time,
                 matching_priority: :supply_driven)

    super
  end

  private

  # Supply-Driven Matching: Offers (sellers) are prioritized, and we try to match
  # available buyers (interests) to each offer.
  def match_offers_to_interests
    Rails.logger.debug "Matching offers to interests"
    @offers.each do |offer|
      message = "Matching offer: #{offer}"
      send_notification(message, @user_id)

      available_offer_quantity = available_quantity(offer) # Remaining unallocated quantity for this offer
      if available_offer_quantity.zero?
        Rails.logger.debug { "Offer #{offer} is fully allocated" }
        # Skip if the entire offer is already allocated
        next
      end

      # Find eligible interests (buyers) who meet the price condition and sort by time priority
      eligible_interests = filter_and_sort_interests(offer)

      Rails.logger.debug { "No eligible interests found for offer: #{offer}" } if eligible_interests.empty?

      eligible_interests.each do |interest|
        offer.reload
        Rails.logger.debug { "Matching offer: #{offer} with quantity #{offer.quantity} allocation_quantity: #{offer.allocation_quantity} to interest: #{interest}" }

        available_offer_quantity = available_quantity(offer)
        break if available_offer_quantity.zero?

        available_interest_quantity = available_quantity(interest)
        # Skip if the entire interest is already allocated
        next if available_interest_quantity.zero?

        allocation_quantity = [available_offer_quantity, available_interest_quantity].min
        # Create the allocation and update allocation quantities
        Allocation.build_from(offer, interest, allocation_quantity, interest.price).save!
      end
    end
  end

  def available_quantity(model)
    # Remaining unallocated quantity for this model
    av_qty = model.quantity - model.allocation_quantity - model.unverified_allocation_quantity
    Rails.logger.debug { "#{model} is fully allocated" } if av_qty.zero?
    av_qty
  end

  # Demand-Driven Matching: Interests (buyers) are prioritized, and we try to match
  # available sellers (offers) to each interest.
  def match_interests_to_offers
    Rails.logger.debug "Matching interests to offers"
    @interests.each do |interest|
      message = "Matching interest: #{interest}"
      send_notification(message, @user_id)

      available_interest_quantity = available_quantity(interest)
      next if available_interest_quantity.zero?

      # Find eligible offers (sellers) who meet the price condition and sort by time priority
      eligible_offers = filter_and_sort_offers(interest)

      Rails.logger.debug { "No eligible offers found for interest: #{interest}" } if eligible_offers.empty?

      eligible_offers.each do |offer|
        interest.reload
        Rails.logger.debug { "Matching interest: #{interest} with quantity #{interest.quantity} allocation_quantity: #{interest.allocation_quantity} to offer: #{offer}" }
        available_interest_quantity = available_quantity(interest)
        break if available_interest_quantity.zero?

        available_offer_quantity = available_quantity(offer)
        next if available_offer_quantity.zero?

        allocation_quantity = [available_offer_quantity, available_interest_quantity].min
        Allocation.build_from(offer, interest, allocation_quantity, offer.price).save!
        break # Break after a full match
      end
    end
  end

  def generate_pro_rata_allocations
    # Step 0: Find the clearing price
    clearing_price = find_clearing_price(offers, interests)

    # Step 1: Filter eligible offers and interests based on the clearing price
    eligible_offers = @offers.select { |offer| offer.price <= clearing_price }
                             .sort_by { |offer| [offer.price, offer.created_at] } # Ascending price, then earlier time

    eligible_interests = @interests.select { |interest| interest.price >= clearing_price }
                                   .sort_by { |interest| [-interest.price, interest.created_at] } # Descending price, then earlier time

    # Step 2: Initialize allocation list
    allocations = []

    # Step 3: Initialize indices for offers and interests
    offer_index = 0
    interest_index = 0

    # Step 4: Greedy Allocation
    while offer_index < eligible_offers.size && interest_index < eligible_interests.size
      offer = eligible_offers[offer_index]
      interest = eligible_interests[interest_index]

      # Determine the quantity to allocate
      allocated_quantity = [offer.quantity, interest.quantity].min

      # Create the allocation
      allocations << {
        offer_id: offer.id,
        interest_id: interest.id,
        quantity: allocated_quantity,
        price: clearing_price
      }

      # Update remaining quantities
      offer.quantity -= allocated_quantity
      interest.quantity -= allocated_quantity

      # Move to next offer or interest if fully allocated
      offer_index += 1 if offer.quantity.zero?
      interest_index += 1 if interest.quantity.zero?
    end

    allocations
  end
end
