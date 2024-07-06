class CustomAllocationJob < AllocationBase
  def perform(secondary_sale_id, user_id)
    Chewy.strategy(:sidekiq) do
      secondary_sale = SecondarySale.find(secondary_sale_id)

      if secondary_sale.lock_allocations
        send_notification("Sale is locked, cannot allocate!", user_id, :danger)
      else

        begin
          init(secondary_sale)
          send_notification("Matching buys and sells ...", user_id, :info)
          match(secondary_sale)
          update_sale(secondary_sale)
          secondary_sale.allocation_status = "Completed"
        rescue StandardError => e
          ExceptionNotifier.notify_exception(e)
          logger.error e.backtrace.join("\n")
          secondary_sale.allocation_status = "Error"
        end

        secondary_sale.save
        send_notification("Sale allocation completed successfully.", user_id, :success)
      end
    end
  end

  def match(secondary_sale)
    interests = secondary_sale.interests.eligible(secondary_sale)
    interests.update_all(allocation_quantity: 0, allocation_percentage: 0)

    offers = secondary_sale.offers.auto_match.approved.order(allocation_quantity: :desc)
    offers.update_all(interest_id: nil, allocation_quantity: 0, allocation_percentage: 0)

    if secondary_sale.custom_matching_fields.present?
      custom_matching_vals = interests.pluck(:custom_matching_vals).uniq

      custom_matching_vals.each do |cmv|
        Rails.logger.debug { "Checking #{cmv}" }
        cmv_interests = interests.where(custom_matching_vals: cmv)
        cmv_offers = offers.where(custom_matching_vals: cmv)
        update_offers(cmv_interests, cmv_offers, secondary_sale, cmv)
      end
    else
      update_offers(interests, offers, secondary_sale)
    end
  end

  def update_offers(interests, offers, secondary_sale, cmv = "")
    total_offered_quantity = offers.sum(:quantity)
    total_interest_quantity = interests.sum(:quantity)

    allocation_percentage = total_offered_quantity.positive? ? (total_interest_quantity * 1.0 / total_offered_quantity).round(4) : 0
    Rails.logger.debug do
      " total_offered_quantity = #{total_offered_quantity},
        total_interest_quantity = #{total_interest_quantity},
        allocation_percentage: #{allocation_percentage}"
    end

    # We need to allocate on a pro rata basis, hence the allocation_percentage computation
    if allocation_percentage <= 1
      interest_percentage = 1
      # We only can allocate  a portion of the offers
      offer_percentage = (1.0 * allocation_percentage).round(6)
    else
      offer_percentage = 1
      # We only can allocate a portion of the interests
      interest_percentage = (1.0 / allocation_percentage).round(6)
    end

    secondary_sale.cmf_allocation_percentage ||= {}
    secondary_sale.cmf_allocation_percentage[cmv] = allocation_percentage

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
end
