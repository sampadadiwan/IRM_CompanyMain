class FundUnitTransferService < Trailblazer::Operation
  step :validate_transfer
  step :transfer_units
  step :send_notification
  left :handle_errors, Output(:failure) => End(:failure)

  def validate_transfer(ctx, quantity:, from_commitment:, to_commitment:, fund:, **)
    valid = true
    if from_commitment.fund_id != fund.id || to_commitment.fund_id != fund.id
      msg = "Commitments are not from the same fund"
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    if from_commitment.unit_type != to_commitment.unit_type
      msg = "Commitments are not the same unit type"
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    if from_commitment.total_fund_units_quantity < quantity
      msg = "From commitment does not have enough units"
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    valid
  end

  def transfer_units(ctx, quantity:, transfer_date:, from_commitment:, to_commitment:, fund:, price:, premium:, **)
    # Get the reason for the transfer
    reason = ctx[:reason].presence || "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}"
    success = false

    FundUnit.transaction do
      # Setup the transfer from the from_commitment
      from_fu = from_commitment.fund_units.create(entity_id: from_commitment.entity_id, unit_type: from_commitment.unit_type, investor_id: from_commitment.investor_id, quantity: -quantity, price:, premium:, fund:, reason:, issue_date: transfer_date, transfer: "out")
      # Setup the transfer to the to_commitment
      to_fu = to_commitment.fund_units.create(entity_id: to_commitment.entity_id, unit_type: to_commitment.unit_type, investor_id: to_commitment.investor_id, quantity:, price:, premium:, fund:, reason:, issue_date: transfer_date, transfer: "in")

      if from_fu.valid? && to_fu.valid?
        success = true
      else
        Rails.logger.error("Error transferring units: #{from_fu.errors.full_messages} #{to_fu.errors.full_messages}")
        ctx[:errors] = from_fu.errors.full_messages
        ctx[:errors] += to_fu.errors.full_messages
        success = false
      end
    end

    success
  end

  def send_notification(_ctx, **)
    # Send notification to the investors
    true
  end

  def handle_errors(ctx, **)
    ctx[:error] ||= "Error transferring units"
    false
  end
end
