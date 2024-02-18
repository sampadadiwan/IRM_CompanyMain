class DefaultUnitAllocationEngine
  def allocate_call(capital_call, reason, user_id)
    @error_msg = []

    if capital_call.fund.unit_types.present?
      capital_call.capital_remittances.verified.each do |cr|
        _, error_msg = allocate_remittance(cr, reason)
        @error_msg << { folio: cr.folio_id, errors: error_msg.join(",") } if error_msg.present?
      end
    end

    cleanup("Unit allocations", user_id)
  end

  def allocate_distribution(capital_distribution, reason, user_id)
    @error_msg = []

    if capital_distribution.fund.unit_types.present?
      capital_distribution.capital_distribution_payments.completed.each do |cdp|
        _, error_msg = allocate_distribution_payment(cdp, reason)
        @error_msg << { folio: cr.folio_id, errors: error_msg.join(",") } if error_msg.present?
      end
    end

    cleanup("Unit redemptions", user_id)
  end

  def allocate_remittance(capital_remittance, reason)
    capital_commitment = capital_remittance.capital_commitment
    capital_call = capital_remittance.capital_call
    unit_type = capital_commitment.unit_type
    unit_price_cents = capital_call.unit_prices[unit_type] ? capital_call.unit_prices[unit_type]["price"] : nil
    unit_premium_cents = capital_call.unit_prices[unit_type] ? capital_call.unit_prices[unit_type]["premium"] : nil
    msg = []

    if  capital_remittance.verified && capital_remittance.collected_amount_cents.positive? &&
        capital_call.unit_prices.present? && capital_commitment.unit_type.present? && unit_price_cents.present? && unit_premium_cents.present?
      # Get the price for the unit type for this commitment from the call

      price_cents = unit_price_cents.to_d * 100
      premium_cents = unit_premium_cents.to_d * 100

      # Sometimes we collect more than the call amount, issue of funds units should be based on lesser of collected amount or call amount
      net_call_amount_cents = (capital_remittance.call_amount_cents - capital_remittance.capital_fee_cents)
      if capital_remittance.collected_amount_cents >= net_call_amount_cents
        amount_cents = net_call_amount_cents
        reason += " Issuing units for net call amount #{net_call_amount_cents}"
      else
        amount_cents = capital_remittance.collected_amount_cents
      end

      quantity = price_cents.positive? ? (amount_cents / (price_cents + premium_cents)) : 0

      fund_unit = new_fund_unit(capital_remittance, unit_type, quantity, price_cents, premium_cents, reason)

      [fund_unit, msg]
    else
      msg = allocate_skip_reasons(capital_remittance)
      Rails.logger.debug msg.join(", ")
      [nil, msg]
    end
  end

  def allocate_skip_reasons(capital_remittance)
    msg = []
    msg << "Skipping fund units generation for #{capital_remittance.folio_id}"
    msg << "Remittance not verified" unless capital_remittance.verified
    msg << "No collected amount" unless capital_remittance.collected_amount_cents.positive?
    msg << "No unit prices in call" if capital_call.unit_prices.blank?
    msg << "No unit type in commitment" if capital_commitment.unit_type.blank?
    msg << "No unit price for commitment" if unit_price_cents.blank?
    msg << "No unit premium for commitment" if unit_premium_cents.blank?
    msg
  end

  def new_fund_unit(capital_remittance, unit_type, quantity, price_cents, premium_cents, reason)
    fund_unit = find_or_new_remittance(capital_remittance, unit_type)

    # Update quantity
    fund_unit.quantity = quantity
    fund_unit.price = (price_cents / 100)
    fund_unit.premium = (premium_cents / 100)
    fund_unit.total_premium_cents = (premium_cents * quantity)
    fund_unit.reason = reason
    fund_unit.issue_date = [capital_remittance.payment_date, capital_remittance.capital_call.due_date].max

    fund_unit.save
    fund_unit
  end

  def allocate_distribution_payment(capital_distribution_payment, reason)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_distribution = capital_distribution_payment.capital_distribution
    msg = []

    if  capital_distribution_payment.completed &&
        capital_distribution_payment.cost_of_investment_cents.positive? &&
        capital_distribution.unit_prices.present? &&
        capital_commitment.unit_type.present?
      # Get the price for the unit type for this commitment from the call
      unit_type = capital_commitment.unit_type
      price_cents = capital_distribution.unit_prices[unit_type].to_d * 100
      # Calculate the quantity to be allocated
      quantity = price_cents.positive? ? (capital_distribution_payment.cost_of_investment_cents / price_cents) : 0

      fund_unit = find_or_new_payment(capital_distribution_payment, unit_type)

      # Update quantity
      fund_unit.quantity = -quantity
      fund_unit.price = (price_cents / 100)
      fund_unit.reason = reason
      fund_unit.issue_date = capital_distribution_payment.payment_date

      fund_unit.save
      [fund_unit, msg]
    else
      msg << "Skipping fund units generation for #{capital_distribution_payment.folio_id}"
      msg << "Payment not completed" unless capital_distribution_payment.completed
      msg << "No payment amount" unless capital_distribution_payment.amount_cents.positive?
      msg << "No unit prices in distrbution" if capital_distribution.unit_prices.blank?
      msg << "No unit type in commitment" if capital_commitment.unit_type.blank?
      Rails.logger.debug msg.join(", ")
      [nil, msg]
    end
  end

  def find_or_new_remittance(capital_remittance, unit_type)
    # Check for existing units, this method needs to be idempotent
    fund_unit = FundUnit.where(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_commitment: capital_remittance.capital_commitment, investor_id: capital_remittance.investor_id, unit_type:, owner: capital_remittance).first

    fund_unit ||= FundUnit.new(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_commitment: capital_remittance.capital_commitment, investor_id: capital_remittance.investor_id, unit_type:, owner: capital_remittance)

    fund_unit
  end

  def find_or_new_payment(capital_distribution_payment, unit_type)
    # Check for existing units, this method needs to be idempotent
    fund_unit = FundUnit.where(entity_id: capital_distribution_payment.entity_id, fund_id: capital_distribution_payment.fund_id, capital_commitment: capital_distribution_payment.capital_commitment, investor_id: capital_distribution_payment.investor_id, unit_type:, owner: capital_distribution_payment).first

    fund_unit ||= FundUnit.new(entity_id: capital_distribution_payment.entity_id, fund_id: capital_distribution_payment.fund_id, capital_commitment: capital_distribution_payment.capital_commitment, investor_id: capital_distribution_payment.investor_id, unit_type:, owner: capital_distribution_payment)

    fund_unit
  end

  def cleanup(case_name, user_id)
    if @error_msg.present?
      msg = "#{case_name} completed, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      msg = "#{case_name} completed"
      send_notification(msg, user_id, :success)
    end
  end

  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end
end
