class DefaultUnitAllocationEngine
  def allocate_call(capital_call, reason)
    if capital_call.fund.unit_types.present?
      capital_call.capital_remittances.each do |cr|
        allocate_remittance(cr, reason)
      end
    end
  end

  def allocate_distribution(capital_distribution, reason)
    if capital_distribution.fund.unit_types.present?
      capital_distribution.capital_distribution_payments.each do |cdp|
        allocate_distribution_payment(cdp, reason)
      end
    end
  end

  def allocate_remittance(capital_remittance, reason)
    capital_commitment = capital_remittance.capital_commitment
    capital_call = capital_remittance.capital_call
    msg = []

    if  capital_remittance.verified && capital_remittance.collected_amount_cents.positive? &&
        capital_call.unit_prices.present? && capital_commitment.unit_type.present?
      # Get the price for the unit type for this commitment from the call
      unit_type = capital_commitment.unit_type
      price_cents = capital_call.unit_prices[unit_type].to_d * 100
      # Calculate the quantity to be allocated
      quantity = price_cents.positive? ? (capital_remittance.collected_amount_cents / price_cents) : 0

      fund_unit = find_or_new_remittance(capital_remittance, unit_type)

      # Update quantity
      fund_unit.quantity = quantity
      fund_unit.price = (price_cents / 100)
      fund_unit.reason = reason

      fund_unit.save
      [fund_unit, msg]
    else
      msg << "Skipping fund units generation"
      msg << "Remittance not verified" unless capital_remittance.verified
      msg << "No collected amount" unless capital_remittance.collected_amount_cents.positive?
      msg << "No unit prices in call" if capital_call.unit_prices.blank?
      msg << "No unit type in commitment" if capital_commitment.unit_type.blank?
      Rails.logger.debug msg.join(", ")
      [nil, msg]
    end
  end

  def allocate_distribution_payment(capital_distribution_payment, reason)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_distribution = capital_distribution_payment.capital_distribution
    msg = []

    if  capital_distribution_payment.completed && capital_distribution_payment.amount_cents.positive? &&
        capital_distribution.unit_prices.present? && capital_commitment.unit_type.present?
      # Get the price for the unit type for this commitment from the call
      unit_type = capital_commitment.unit_type
      price_cents = capital_distribution.unit_prices[unit_type].to_d * 100
      # Calculate the quantity to be allocated
      quantity = price_cents.positive? ? (capital_distribution_payment.amount_cents / price_cents) : 0

      fund_unit = find_or_new_payment(capital_distribution_payment, unit_type)

      # Update quantity
      fund_unit.quantity = -quantity
      fund_unit.price = (price_cents / 100)
      fund_unit.reason = reason

      fund_unit.save
      [fund_unit, msg]
    else
      msg << "Skipping fund units generation"
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
end
