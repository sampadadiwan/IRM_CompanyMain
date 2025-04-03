class DefaultUnitAllocationEngine
  include CurrencyHelper

  # Allocates units for a capital call based on remittances
  def allocate_call(capital_call, reason, user_id)
    @error_msg = []

    # Check if the fund has unit types
    if capital_call.fund.unit_types.present?
      # Process each verified capital remittance
      capital_call.capital_remittances.verified.each do |cr|
        _, error_msg = allocate_remittance(cr, reason)
        # Collect errors for each remittance, if any
        @error_msg << { folio: cr.folio_id, errors: error_msg.join(",") } if error_msg.present?
      end
    end

    # Perform cleanup and send notifications
    cleanup("Unit allocations", user_id)
  end

  # Allocates units for a capital distribution based on payments
  def allocate_distribution(capital_distribution, reason, user_id)
    @error_msg = []

    # Check if the fund has unit types
    if capital_distribution.fund.unit_types.present?
      # Process each completed capital distribution payment
      capital_distribution.capital_distribution_payments.completed.each do |cdp|
        _, error_msg = allocate_distribution_payment(cdp, reason)
        # Collect errors for each payment, if any
        @error_msg << { folio: cdp.capital_commitment.folio_id, errors: error_msg.join(",") } if error_msg.present?
      end
    end

    # Perform cleanup and send notifications
    cleanup("Unit redemptions", user_id)
  end

  # Allocates units for a specific remittance
  def allocate_remittance(capital_remittance, reason)
    capital_commitment = capital_remittance.capital_commitment
    capital_call = capital_remittance.capital_call
    unit_type = capital_commitment.unit_type
    unit_price_cents = capital_call.unit_prices[unit_type] ? capital_call.unit_prices[unit_type]["price"] : nil
    unit_premium_cents = capital_call.unit_prices[unit_type] ? capital_call.unit_prices[unit_type]["premium"] : nil

    # Validate remittance and required data
    if  capital_remittance.verified && capital_remittance.collected_amount_cents.positive? &&
        capital_call.unit_prices.present? && capital_commitment.unit_type.present? && unit_price_cents.present? && unit_premium_cents.present? &&
        capital_remittance.fund_units.blank?

      # Calculate price and premium in cents
      price_cents = unit_price_cents.to_d * 100
      premium_cents = unit_premium_cents.to_d * 100

      # Determine the amount to allocate based on collected or call amount
      # We also need to check if units have already been allocated, and if so only allocate remaining amount
      net_call_amount_cents = capital_remittance.call_amount_cents
      if capital_remittance.collected_amount_cents >= net_call_amount_cents
        amount_cents = net_call_amount_cents
        reason += " - Issuing units for net call amount #{money_to_currency(Money.new(net_call_amount_cents, capital_remittance.fund.currency))}"
      else
        amount_cents = capital_remittance.collected_amount_cents
        reason += " - Issuing units for net collected amount #{money_to_currency(capital_remittance.collected_amount)}"
      end

      # Calculate the quantity of units to allocate
      quantity = price_cents.positive? ? (amount_cents / (price_cents + premium_cents)) : 0

      # Create or update fund unit
      fund_unit, msg = new_fund_unit(capital_remittance, unit_type, quantity, price_cents, premium_cents, reason)

      [fund_unit, msg]
    else
      # Collect reasons for skipping allocation
      msg = allocate_skip_reasons(capital_remittance)
      Rails.logger.debug msg.join(", ")
      [nil, msg]
    end
  end

  # Generates reasons for skipping fund unit allocation
  def allocate_skip_reasons(capital_remittance)
    msg = []
    msg << "Skipping fund units generation for #{capital_remittance.folio_id}"
    msg << "Remittance not verified" unless capital_remittance.verified
    msg << "No collected amount" unless capital_remittance.collected_amount_cents.positive?
    msg << "No unit prices in call" if capital_remittance.capital_call.unit_prices.blank?
    unit_type = capital_remittance.capital_commitment.unit_type
    msg << "No unit type in commitment" if unit_type.blank?
    msg << "Invalid unit price in call, for unit type" if unit_type.present? && capital_remittance.capital_call.unit_prices[unit_type].blank?
    msg << "Fund Units already allocated" if capital_remittance.fund_units.present?
    msg
  end

  # Creates or updates a fund unit for a remittance
  def new_fund_unit(capital_remittance, unit_type, quantity, price_cents, premium_cents, reason)
    fund_unit = find_or_new_remittance(capital_remittance, unit_type)

    # Update fund unit attributes
    fund_unit.quantity = quantity
    fund_unit.price_cents = price_cents
    fund_unit.premium_cents = premium_cents
    fund_unit.total_premium_cents = (premium_cents * quantity)
    fund_unit.reason = reason

    # Set issue date based on payment or due date
    fund_unit.issue_date = if capital_remittance.payment_date
                             [capital_remittance.payment_date, capital_remittance.capital_call.due_date].max
                           else
                             capital_remittance.capital_call.due_date
                           end

    # Save fund unit and return result
    if fund_unit.save
      [fund_unit, []]
    else
      [fund_unit, fund_unit.errors]
    end
  end

  # Allocates units for a specific distribution payment
  def allocate_distribution_payment(capital_distribution_payment, reason)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_distribution = capital_distribution_payment.capital_distribution
    msg = []

    # Validate payment and required data
    if  capital_distribution_payment.completed &&
        capital_distribution_payment.cost_of_investment_with_fees_cents.positive? &&
        capital_distribution.unit_prices.present? &&
        capital_commitment.unit_type.present?

      # Get the price for the unit type
      unit_type = capital_commitment.unit_type
      price_cents = capital_distribution.unit_prices[unit_type].to_d * 100

      # Calculate the quantity to be allocated
      quantity = price_cents.positive? ? (capital_distribution_payment.cost_of_investment_with_fees_cents / price_cents) : 0

      # Create or update fund unit
      fund_unit = find_or_new_payment(capital_distribution_payment, unit_type)

      # Update fund unit attributes
      fund_unit.quantity = -quantity
      fund_unit.price = (price_cents / 100)
      fund_unit.reason = reason
      fund_unit.issue_date = capital_distribution_payment.payment_date

      # Save fund unit and return result
      fund_unit.save
      [fund_unit, msg]
    else
      # Collect reasons for skipping allocation
      msg << "Skipping fund units generation for #{capital_distribution_payment.folio_id}"
      msg << "Payment not completed" unless capital_distribution_payment.completed
      msg << "No payment amount" unless capital_distribution_payment.cost_of_investment_with_fees_cents.positive?
      msg << "No unit prices in distribution" if capital_distribution.unit_prices.blank?
      msg << "No unit type in commitment" if capital_commitment.unit_type.blank?
      Rails.logger.debug msg.join(", ")
      [nil, msg]
    end
  end

  # Finds or initializes a fund unit for a remittance
  def find_or_new_remittance(capital_remittance, unit_type)
    # Check for existing units, this method needs to be idempotent
    fund_unit = FundUnit.where(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_commitment: capital_remittance.capital_commitment, investor_id: capital_remittance.investor_id, unit_type:, owner: capital_remittance).first

    # Initialize a new fund unit if none exists
    fund_unit ||= FundUnit.new(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_commitment: capital_remittance.capital_commitment, investor_id: capital_remittance.investor_id, unit_type:, owner: capital_remittance)

    fund_unit
  end

  # Finds or initializes a fund unit for a distribution payment
  def find_or_new_payment(capital_distribution_payment, unit_type)
    # Check for existing units, this method needs to be idempotent
    fund_unit = FundUnit.where(entity_id: capital_distribution_payment.entity_id, fund_id: capital_distribution_payment.fund_id, capital_commitment: capital_distribution_payment.capital_commitment, investor_id: capital_distribution_payment.investor_id, unit_type:, owner: capital_distribution_payment).first

    # Initialize a new fund unit if none exists
    fund_unit ||= FundUnit.new(entity_id: capital_distribution_payment.entity_id, fund_id: capital_distribution_payment.fund_id, capital_commitment: capital_distribution_payment.capital_commitment, investor_id: capital_distribution_payment.investor_id, unit_type:, owner: capital_distribution_payment)

    fund_unit
  end

  # Handles cleanup and sends notifications after allocation
  def cleanup(case_name, user_id)
    if @error_msg.present?
      # Notify user of errors
      msg = "#{case_name} completed, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      # Notify user of successful completion
      msg = "#{case_name} completed"
      send_notification(msg, user_id, :success)
    end
  end

  # Sends a notification to the user
  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end
end
