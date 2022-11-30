class FundRaiseAllocationJob < AllocationBase
  def perform(secondary_sale_id)
    Chewy.strategy(:atomic) do
      secondary_sale = SecondarySale.find(secondary_sale_id)

      unless secondary_sale.lock_allocations

        begin
          init(secondary_sale)
          update_interests(secondary_sale)
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

  # For a FundRaise there are no offers - the total_offered_quantity is specified from the UI
  def get_total_offered_quantity(secondary_sale)
    secondary_sale.total_offered_quantity
  end

  # For a FundRaise there are no offers
  def get_total_offered_allocation_quantity(_secondary_sale)
    0
  end

  def update_interests(secondary_sale)
    interests = secondary_sale.interests.eligible(secondary_sale)

    interest_percentage = if secondary_sale.allocation_percentage <= 1
                            1
                          else
                            (1.0 / secondary_sale.allocation_percentage).round(6)
                          end

    Rails.logger.debug { "allocating #{interest_percentage}% of interests" }

    # We have more interests #{100.00 * interest_percentage},
    interests.update_all("allocation_percentage = #{100.00 * interest_percentage},
      allocation_quantity = ceil(quantity * #{interest_percentage}),
      final_price = #{secondary_sale.final_price},
      allocation_amount_cents = (ceil(quantity * #{interest_percentage}) * #{secondary_sale.final_price * 100})")
  end
end
