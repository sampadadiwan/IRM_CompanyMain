# rubocop:disable Rails/SkipsModelValidations
# rubocop:disable Metrics/BlockLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
class FundUnitTransferService < Trailblazer::Operation
  step :generate_transfer_token
  step :validate_transfer
  step :transfer_units
  step :transfer_account_entries
  step :transfer_remittances
  step :transfer_distributions
  step :apply_commitment_adjustments
  step :counter_culture_fix_counts
  step :send_notification
  left :handle_errors, Output(:failure) => End(:failure)

  def generate_transfer_token(ctx, **)
    ctx[:transfer_token] = SecureRandom.uuid
  end

  def validate_transfer(ctx, transfer_ratio:, from_commitment:, to_commitment:, fund:, **)
    quantity = (from_commitment.total_fund_units_quantity * transfer_ratio).to_f
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

  def transfer_units(ctx, transfer_ratio:, transfer_date:, from_commitment:, to_commitment:, fund:, price:, premium:, **)
    # Get the reason for the transfer
    reason = ctx[:reason].presence || "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}. Transfer ID: #{ctx[:transfer_token]}"
    success = false
    price_cents = price.to_d * 100.0
    premium_cents = premium.to_d * 100.0
    # The transfer quantity, is the product of the from_commitment's units_quantity and the transfer_ratio
    quantity = (from_commitment.total_fund_units_quantity * transfer_ratio).to_f
    FundUnit.transaction do
      # Setup the transfer from the from_commitment
      from_fu = from_commitment.fund_units.create(entity_id: from_commitment.entity_id, unit_type: from_commitment.unit_type, investor_id: from_commitment.investor_id, quantity: -quantity, price_cents:, premium_cents:, fund:, reason:, issue_date: transfer_date, transfer: "out")
      # Setup the transfer to the to_commitment
      to_fu = to_commitment.fund_units.create(entity_id: to_commitment.entity_id, unit_type: to_commitment.unit_type, investor_id: to_commitment.investor_id, quantity:, price_cents:, premium_cents:, fund:, reason:, issue_date: transfer_date, transfer: "in")

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

  # This is used to transfer the account entries from the from_commitment to the to_commitment, based on the transfer_account_entries parameter and account_entries_excluded and transfer_ratio
  def transfer_account_entries(ctx, **)
    if ctx[:transfer_account_entries]
      # Transfer the account entries
      from_commitment = ctx[:from_commitment]
      to_commitment = ctx[:to_commitment]
      transfer_ratio = ctx[:transfer_ratio]
      retained_ratio = 1 - transfer_ratio

      account_entries_transferred = 0
      account_entries_ignored = 0

      from_commitment.account_entries.each do |entry|
        if ctx[:account_entries_excluded].blank? || ctx[:account_entries_excluded].exclude?(entry.name)
          new_entry = entry.dup
          new_entry.json_fields["Transfer ID"] = ctx[:transfer_token]
          new_entry.json_fields["Orig Amount"] = entry.amount_cents
          new_entry.capital_commitment_id = to_commitment.id
          new_entry.amount_cents *= transfer_ratio
          new_entry.folio_amount_cents *= transfer_ratio
          new_entry.tracking_amount_cents *= transfer_ratio
          new_entry.created_at = Time.zone.now
          new_entry.updated_at = Time.zone.now
          new_entry.json_fields["Notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, original entry ID: #{entry.id}"

          entry.json_fields["Transfer ID"] = ctx[:transfer_token]
          entry.json_fields["Orig Amount"] = entry.amount_cents
          entry.amount_cents *= retained_ratio
          entry.folio_amount_cents *= retained_ratio
          entry.tracking_amount_cents *= retained_ratio
          entry.json_fields["Notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, original entry ID: #{entry.id}"

          AccountEntry.transaction do
            # Update without callbacks
            entry.update_columns(
              amount_cents: (entry.amount_cents * retained_ratio),
              folio_amount_cents: (entry.folio_amount_cents * retained_ratio),
              tracking_amount_cents: (entry.tracking_amount_cents * retained_ratio),
              json_fields: entry.json_fields,
              updated_at: Time.current # omit if you truly don't want to touch timestamps
            )
            # Insert without callbacks
            AccountEntry.insert_all!([new_entry.attributes.except("generated_deleted")])
          end
          account_entries_transferred += 1
        else
          account_entries_ignored += 1
        end
      end
    end
    true
  end

  # This is used to transfer the remittances and payments from the from_commitment to the to_commitment, based on the transfer_ratio
  def transfer_remittances(ctx, **)
    from_commitment = ctx[:from_commitment]
    to_commitment = ctx[:to_commitment]
    transfer_ratio = ctx[:transfer_ratio]
    retained_ratio = 1 - transfer_ratio
    token = ctx[:transfer_token]

    remittances_transferred = 0

    from_commitment.capital_remittances.each do |remittance|
      new_remittance = remittance.dup
      new_remittance.json_fields["Transfer ID"] = ctx[:transfer_token]
      new_remittance.json_fields["Orig Call Amount"] = remittance.call_amount_cents
      new_remittance.json_fields["Orig Collected Amount"] = remittance.collected_amount_cents
      new_remittance.json_fields["Orig Committed Amount"] = remittance.committed_amount_cents
      new_remittance.capital_commitment_id = to_commitment.id
      new_remittance.call_amount_cents *= transfer_ratio
      new_remittance.collected_amount_cents *= transfer_ratio
      new_remittance.committed_amount_cents *= transfer_ratio
      new_remittance.folio_call_amount_cents *= transfer_ratio
      new_remittance.folio_collected_amount_cents *= transfer_ratio
      new_remittance.folio_committed_amount_cents *= transfer_ratio
      new_remittance.capital_fee_cents *= transfer_ratio
      new_remittance.other_fee_cents *= transfer_ratio
      new_remittance.folio_capital_fee_cents *= transfer_ratio
      new_remittance.folio_other_fee_cents *= transfer_ratio
      new_remittance.computed_amount_cents *= transfer_ratio
      new_remittance.percentage *= transfer_ratio
      new_remittance.arrear_folio_amount_cents *= transfer_ratio
      new_remittance.arrear_amount_cents *= transfer_ratio
      new_remittance.tracking_collected_amount_cents *= transfer_ratio
      new_remittance.tracking_call_amount_cents *= transfer_ratio
      new_remittance.created_at = Time.zone.now
      new_remittance.updated_at = Time.zone.now
      new_remittance.notes ||= ""
      new_remittance.notes += " Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, original remittance ID: #{remittance.id}"

      remittance.json_fields["Transfer ID"] = ctx[:transfer_token]
      remittance.json_fields["Orig Call Amount"] = remittance.call_amount_cents
      remittance.json_fields["Orig Collected Amount"] = remittance.collected_amount_cents
      remittance.json_fields["Orig Committed Amount"] = remittance.committed_amount_cents
      remittance.call_amount_cents *= retained_ratio
      remittance.collected_amount_cents *= retained_ratio
      remittance.committed_amount_cents *= retained_ratio
      remittance.folio_call_amount_cents *= retained_ratio
      remittance.folio_collected_amount_cents *= retained_ratio
      remittance.folio_committed_amount_cents *= retained_ratio
      remittance.capital_fee_cents *= retained_ratio
      remittance.other_fee_cents *= retained_ratio
      remittance.folio_capital_fee_cents *= retained_ratio
      remittance.folio_other_fee_cents *= retained_ratio
      remittance.computed_amount_cents *= retained_ratio
      remittance.percentage *= retained_ratio
      remittance.arrear_folio_amount_cents *= retained_ratio
      remittance.arrear_amount_cents *= retained_ratio
      remittance.tracking_collected_amount_cents *= retained_ratio
      remittance.tracking_call_amount_cents *= retained_ratio
      remittance.notes ||= ""
      remittance.notes += " Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}"

      CapitalRemittance.transaction do
        # Update without callbacks
        remittance.update_columns(
          call_amount_cents: remittance.call_amount_cents,
          collected_amount_cents: remittance.collected_amount_cents,
          committed_amount_cents: remittance.committed_amount_cents,
          folio_call_amount_cents: remittance.folio_call_amount_cents,
          folio_collected_amount_cents: remittance.folio_collected_amount_cents,
          folio_committed_amount_cents: remittance.folio_committed_amount_cents,
          capital_fee_cents: remittance.capital_fee_cents,
          other_fee_cents: remittance.other_fee_cents,
          folio_capital_fee_cents: remittance.folio_capital_fee_cents,
          folio_other_fee_cents: remittance.folio_other_fee_cents,
          computed_amount_cents: remittance.computed_amount_cents,
          percentage: remittance.percentage,
          arrear_folio_amount_cents: remittance.arrear_folio_amount_cents,
          arrear_amount_cents: remittance.arrear_amount_cents,
          tracking_collected_amount_cents: remittance.tracking_collected_amount_cents,
          tracking_call_amount_cents: remittance.tracking_call_amount_cents,
          json_fields: remittance.json_fields,
          notes: remittance.notes
        )

        CapitalRemittance.insert_all([new_remittance.attributes])
        # Now get back the newly created remittance using the Transfer ID
        scope = CapitalRemittance.where(capital_call_id: remittance.capital_call_id, capital_commitment_id: to_commitment.id)

        scope = case ActiveRecord::Base.connection.adapter_name
                when /Mysql/i # For prod / staging env
                  scope.where("json_fields ->> '$.\"Transfer ID\"' = ?", token)
                when /SQLite/i # For the test env
                  # json_extract returns quoted JSON for strings; compare against JSON(value)
                  scope
                .where(<<~SQL.squish, token)
                  CASE
                    WHEN json_valid(json_fields)
                      THEN json_extract(json_fields, '$."Transfer ID"')
                    ELSE NULL
                  END = ?
                SQL
                else # PostgreSQL, etc.
                  scope.where("json_fields ->> 'Transfer ID' = ?", token)
                end

        new_remittance_id = scope.pick(:id) # Rails 7+: returns a single value

        # Now adjust the capital_remittance_payments
        remittance.capital_remittance_payments.each do |payment|
          new_payment = payment.dup
          new_payment.json_fields["Transfer ID"] = ctx[:transfer_token]
          new_payment.json_fields["Orig Amount"] = payment.amount_cents
          new_payment.capital_remittance_id = new_remittance_id
          new_payment.amount_cents *= transfer_ratio
          new_payment.folio_amount_cents *= transfer_ratio
          new_payment.tracking_amount_cents *= transfer_ratio
          new_payment.created_at = Time.zone.now
          new_payment.updated_at = Time.zone.now

          # Insert without callbacks
          CapitalRemittancePayment.insert_all([new_payment.attributes])

          payment.json_fields["Transfer ID"] = ctx[:transfer_token]
          payment.json_fields["Orig Amount"] = payment.amount_cents
          payment.amount_cents *= retained_ratio
          payment.folio_amount_cents *= retained_ratio
          payment.tracking_amount_cents *= retained_ratio

          # Update without callbacks
          payment.update_columns(
            amount_cents: payment.amount_cents,
            folio_amount_cents: payment.folio_amount_cents,
            tracking_amount_cents: payment.tracking_amount_cents,
            json_fields: payment.json_fields
          )
        end
      end
      remittances_transferred += 1
    end

    true
  end

  def transfer_distributions(ctx, from_commitment:, to_commitment:, **)
    transfer_ratio = ctx[:transfer_ratio]
    retained_ratio = 1 - transfer_ratio

    from_commitment.capital_distribution_payments.each do |payment|
      new_payment = payment.dup
      new_payment.json_fields["Transfer ID"] = ctx[:transfer_token]
      new_payment.json_fields["Orig Gross Payable"] = payment.gross_payable_cents
      new_payment.json_fields["Orig Units Quantity"] = payment.units_quantity

      new_payment.capital_commitment_id = to_commitment.id
      new_payment.income_cents *= transfer_ratio
      new_payment.percentage *= transfer_ratio
      new_payment.units_quantity *= transfer_ratio
      new_payment.cost_of_investment_cents *= transfer_ratio
      new_payment.folio_amount_cents *= transfer_ratio
      new_payment.capital_fee_cents *= transfer_ratio
      new_payment.other_fee_cents *= transfer_ratio
      new_payment.net_of_account_entries_cents *= transfer_ratio
      new_payment.net_payable_cents *= transfer_ratio
      new_payment.income_with_fees_cents *= transfer_ratio
      new_payment.cost_of_investment_with_fees_cents *= transfer_ratio
      new_payment.reinvestment_cents *= transfer_ratio
      new_payment.reinvestment_with_fees_cents *= transfer_ratio
      new_payment.gross_payable_cents *= transfer_ratio
      new_payment.gross_of_account_entries_cents *= transfer_ratio
      new_payment.tracking_net_payable_cents *= transfer_ratio
      new_payment.tracking_gross_payable_cents *= transfer_ratio
      new_payment.tracking_reinvestment_with_fees_cents *= transfer_ratio

      # Insert without callbacks
      CapitalDistributionPayment.insert_all([new_payment.attributes])

      payment.json_fields["Transfer ID"] = ctx[:transfer_token]
      payment.json_fields["Orig Gross Payable"] = payment.gross_payable_cents
      payment.json_fields["Orig Units Quantity"] = payment.units_quantity
      payment.income_cents *= retained_ratio
      payment.percentage *= retained_ratio
      payment.units_quantity *= retained_ratio
      payment.cost_of_investment_cents *= retained_ratio
      payment.folio_amount_cents *= retained_ratio
      payment.capital_fee_cents *= retained_ratio
      payment.other_fee_cents *= retained_ratio
      payment.net_of_account_entries_cents *= retained_ratio
      payment.net_payable_cents *= retained_ratio
      payment.income_with_fees_cents *= retained_ratio
      payment.cost_of_investment_with_fees_cents *= retained_ratio
      payment.reinvestment_cents *= retained_ratio
      payment.reinvestment_with_fees_cents *= retained_ratio
      payment.gross_payable_cents *= retained_ratio
      payment.gross_of_account_entries_cents *= retained_ratio
      payment.tracking_net_payable_cents *= retained_ratio
      payment.tracking_gross_payable_cents *= retained_ratio
      payment.tracking_reinvestment_with_fees_cents *= retained_ratio

      # Update without callbacks
      payment.update_columns(
        income_cents: payment.income_cents,
        percentage: payment.percentage,
        units_quantity: payment.units_quantity,
        cost_of_investment_cents: payment.cost_of_investment_cents,
        folio_amount_cents: payment.folio_amount_cents,
        capital_fee_cents: payment.capital_fee_cents,
        other_fee_cents: payment.other_fee_cents,
        net_of_account_entries_cents: payment.net_of_account_entries_cents,
        net_payable_cents: payment.net_payable_cents,
        income_with_fees_cents: payment.income_with_fees_cents,
        cost_of_investment_with_fees_cents: payment.cost_of_investment_with_fees_cents,
        reinvestment_cents: payment.reinvestment_cents,
        reinvestment_with_fees_cents: payment.reinvestment_with_fees_cents,
        gross_payable_cents: payment.gross_payable_cents,
        gross_of_account_entries_cents: payment.gross_of_account_entries_cents,
        tracking_net_payable_cents: payment.tracking_net_payable_cents,
        tracking_gross_payable_cents: payment.tracking_gross_payable_cents,
        tracking_reinvestment_with_fees_cents: payment.tracking_reinvestment_with_fees_cents
      )
    end
    true
  end

  def apply_commitment_adjustments(ctx, from_commitment:, to_commitment:, fund:, **)
    transfer_ratio = ctx[:transfer_ratio]

    # Do NOT put this in a transaction, adjustments do not work if put in a transaction, as they have counter_culture which execute_after_commit

    to_ca = CommitmentAdjustment.new(
      fund_id: fund.id,
      entity_id: to_commitment.entity_id,
      capital_commitment_id: to_commitment.id,
      amount_cents: from_commitment.committed_amount_cents * transfer_ratio,
      folio_amount_cents: from_commitment.folio_committed_amount_cents * transfer_ratio,
      adjustment_type: "Transfer",
      reason: "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, Transfer ID: #{ctx[:transfer_token]}",
      as_of: ctx[:transfer_date]
    )

    AdjustmentCreate.call(commitment_adjustment: to_ca)

    from_ca = CommitmentAdjustment.new(
      fund_id: fund.id,
      entity_id: from_commitment.entity_id,
      capital_commitment_id: from_commitment.id,
      amount_cents: -from_commitment.committed_amount_cents * transfer_ratio,
      folio_amount_cents: -from_commitment.folio_committed_amount_cents * transfer_ratio,
      adjustment_type: "Transfer",
      reason: "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, Transfer ID: #{ctx[:transfer_token]}",
      as_of: ctx[:transfer_date]
    )

    AdjustmentCreate.call(commitment_adjustment: from_ca)

    true
  end

  def counter_culture_fix_counts(_ctx, fund:, **)
    CapitalRemittancePayment.counter_culture_fix_counts where: { 'capital_remittance_payments.fund_id': fund.id }
    CapitalRemittance.counter_culture_fix_counts where: { 'capital_remittances.fund_id': fund.id }
    CapitalDistributionPayment.counter_culture_fix_counts where: { 'capital_distribution_payments.fund_id': fund.id }
    FundUnit.counter_culture_fix_counts where: { 'fund_units.fund_id': fund.id }
    CapitalCommitment.counter_culture_fix_counts where: { 'capital_commitments.fund_id': fund.id }
  end
end
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/BlockLength
# rubocop:enable Rails/SkipsModelValidations
