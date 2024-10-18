# app/services/base_allocation_engine.rb
class BaseAllocationEngine
  def initialize(secondary_sale, user_id:, priority: :time, matching_priority: :supply_driven)
    # Secondary sale object
    @secondary_sale = secondary_sale
    # Either :supply_driven or :demand_driven
    @matching_priority = matching_priority.downcase.strip.parameterize.underscore.to_sym
    # The user ID to send notifications
    @user_id = user_id
    # Either :time or :price
    @priority = priority.to_s.downcase.to_sym

    if @priority == :time
      # List of available offers (sellers) ordered by time priority
      @offers = @secondary_sale.offers.approved.order(created_at: :asc)
      # List of available interests (buyers) ordered by time priority
      @interests = @secondary_sale.interests.short_listed.order(created_at: :asc)
    elsif @priority == :price
      # List of available offers (sellers) ordered by price priority
      @offers = @secondary_sale.offers.approved.order(price: :desc, created_at: :asc)
      # List of available interests (buyers) ordered by price priority
      @interests = @secondary_sale.interests.short_listed.order(price: :asc, created_at: :asc)
    else
      message = "Invalid priority #{@priority}. Must be :time or :price"
      send_notification(message, @user_id, "danger")
      raise ArgumentError, message
    end

    Rails.logger.debug { "Secondary sale: #{@secondary_sale}, matching priority: #{@matching_priority}, priority: #{@priority}" }
    Rails.logger.debug { "Offers: #{@offers.count}, Interests: #{@interests.count}" }
  end

  def cleanup
    # Remove all existing allocations for this secondary sale, which are unverified
    message = "Cleaning up unverified allocations for secondary sale: #{@secondary_sale}"
    Rails.logger.debug { message }
    send_notification(message, @user_id)
    @secondary_sale.allocations.unverified.each(&:destroy)
  end

  # Match function decides whether to match offers to interests (supply-driven)
  # or interests to offers (demand-driven), based on the matching_priority parameter.
  def match
    cleanup

    if @matching_priority == :supply_driven
      match_offers_to_interests
    elsif @matching_priority == :demand_driven
      match_interests_to_offers
    else
      message = "Invalid matching priority. Must be :supply_driven or :demand_driven"
      send_notification(message, @user_id, "danger")
      raise ArgumentError, message
    end

    message = "Matching completed successfully"
    send_notification(message, @user_id)
    @secondary_sale.reload.allocations
  end

  protected

  # Filter and sort interests (buyers) based on the matching priority and price conditions.
  def filter_and_sort_interests(offer)
    @interests.where(price: offer.price..).order(created_at: :asc) # Sort by submission time for time priority
  end

  # Filter and sort offers (sellers) based on the matching priority and price conditions.
  def filter_and_sort_offers(interest)
    @offers.where(price: ..interest.price).order(created_at: :asc) # Sort by submission time for time priority
  end

  def send_notification(message, user_id, level = "success")
    Rails.logger.debug { message }
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end

  def find_clearing_price(offers, interests)
    # Step 1: Sort offers by price (ascending) and interests by price (descending)
    sorted_offers = offers.sort_by(&:price)
    sorted_interests = interests.sort_by { |interest| -interest.price }

    # Step 2: Initialize cumulative supply and demand
    cumulative_supply = 0
    cumulative_demand = 0

    # Step 3: Find the clearing price by comparing supply and demand
    clearing_price = nil
    offer_index = 0
    interest_index = 0

    while offer_index < sorted_offers.length && interest_index < sorted_interests.length
      current_offer = sorted_offers[offer_index]
      current_interest = sorted_interests[interest_index]

      if current_interest.price >= current_offer.price
        # Update cumulative supply and demand
        cumulative_supply += current_offer.quantity
        cumulative_demand += current_interest.quantity

        # If supply and demand meet or cross, set clearing price
        clearing_price = if cumulative_demand >= cumulative_supply
                           current_offer.price
                         else
                           current_interest.price
                         end

        # Move to the next offer and interest
        offer_index += 1
        interest_index += 1
      else
        # No match, break the loop
        break
      end
    end

    # Return the clearing price if found
    clearing_price
  end
end
