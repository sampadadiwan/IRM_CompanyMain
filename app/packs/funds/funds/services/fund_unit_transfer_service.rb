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
  step :completed
  left :handle_errors, Output(:failure) => End(:failure)

  def generate_transfer_token(ctx, transfer:, **)
    ctx[:transfer_token]  = SecureRandom.uuid
    # Store ratio as BigDecimal to avoid float rounding throughout the pipeline.
    ctx[:transfer_ratio]  = BigDecimal(transfer.transfer_ratio.to_s) / 100
    ctx[:from_commitment] = transfer.from_commitment
    ctx[:to_commitment]   = transfer.to_commitment
    ctx[:fund]            = transfer.fund
    ctx[:transfer_date]   = transfer.transfer_date
    ctx[:price]           = BigDecimal((transfer.price || 0).to_s)
    ctx[:premium]         = BigDecimal((transfer.premium || 0).to_s)
    ctx[:transfer_account_entries] = transfer.transfer_account_entries
    ctx[:account_entries_excluded] = transfer.account_entries_excluded.present? ? transfer.account_entries_excluded.split(",").map(&:strip) : []
    transfer.transfer_token = ctx[:transfer_token]
    # Skip model validations here — business rules are enforced in validate_transfer.
    # generate_transfer_token is only responsible for minting the token; a failed
    # save here would swallow the real validation error message.
    transfer.save(validate: false)
    true
  end

  def validate_transfer(ctx, transfer_ratio:, from_commitment:, to_commitment:, fund:, **)
    # Ratio must be valid before we compute quantity to avoid misleading "no units" errors.
    if transfer_ratio <= 0
      ctx[:error] = "Transfer ratio must be greater than 0."
      Rails.logger.error(ctx[:error])
      return false
    end
    if transfer_ratio > 1
      ctx[:error] = "Transfer ratio must be 100 or less."
      Rails.logger.error(ctx[:error])
      return false
    end

    quantity = (BigDecimal(from_commitment.total_fund_units_quantity.to_s) * transfer_ratio).round(10)
    valid = true
    msg = ""
    if from_commitment.fund_id != fund.id || to_commitment.fund_id != fund.id
      msg += "Commitments are not from the same fund."
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    if from_commitment.unit_type != to_commitment.unit_type
      msg += "Commitments are not the same unit type."
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    if quantity <= 0 || BigDecimal(from_commitment.total_fund_units_quantity.to_s) < quantity
      msg += "From commitment does not have enough units."
      Rails.logger.error(msg)
      ctx[:error] = msg
      valid = false
    end
    valid
  end

  def transfer_units(ctx, transfer_ratio:, transfer_date:, from_commitment:, to_commitment:, fund:, price:, premium:, **)
    reason = ctx[:reason].presence || "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}. transfer_id: #{ctx[:transfer_token]}"
    success = false
    price_cents   = (price   * 100).round(0)
    premium_cents = (premium * 100).round(0)
    quantity = (BigDecimal(from_commitment.total_fund_units_quantity.to_s) * transfer_ratio).round(10)
    FundUnit.transaction do
      from_fu = from_commitment.fund_units.create(
        entity_id: from_commitment.entity_id, unit_type: from_commitment.unit_type,
        investor_id: from_commitment.investor_id, quantity: -quantity,
        price_cents:, premium_cents:, fund:, reason:, issue_date: transfer_date, transfer: "out"
      )
      to_fu = to_commitment.fund_units.create(
        entity_id: to_commitment.entity_id, unit_type: to_commitment.unit_type,
        investor_id: to_commitment.investor_id, quantity:,
        price_cents:, premium_cents:, fund:, reason:, issue_date: transfer_date, transfer: "in"
      )

      if from_fu.valid? && to_fu.valid?
        success = true
      else
        messages = (from_fu.errors.full_messages + to_fu.errors.full_messages).join(", ")
        Rails.logger.error("Error transferring units: #{messages}")
        ctx[:error] = messages
        raise ActiveRecord::Rollback
      end
    end

    success
  end

  def send_notification(_ctx, **)
    # Send notification to the investors
    true
  end

  def handle_errors(ctx, transfer:, **)
    ctx[:error] ||= "Error transferring units"
    Rails.logger.error(ctx[:error])

    transfer.status = "Failed: #{ctx[:error]}"
    transfer.save

    false
  end

  def transfer_account_entries(ctx, **)
    if ctx[:transfer_account_entries]
      # Transfer the account entries
      from_commitment = ctx[:from_commitment]
      to_commitment = ctx[:to_commitment]

      from_commitment.account_entries.each do |entry|
        if ctx[:account_entries_excluded].blank? || ctx[:account_entries_excluded].exclude?(entry.name)
          transfer_ratio = ctx[:transfer_ratio]
          retained_ratio = 1 - transfer_ratio
        else
          transfer_ratio = BigDecimal("1")
          retained_ratio = BigDecimal("1")
        end

        orig_amount   = BigDecimal(entry.amount_cents.to_s)
        orig_folio    = BigDecimal(entry.folio_amount_cents.to_s)
        orig_tracking = BigDecimal(entry.tracking_amount_cents.to_s)

        new_entry = entry.dup
        new_entry.folio_id        = to_commitment.folio_id
        new_entry.investor_id     = to_commitment.investor_id
        new_entry.commitment_name = to_commitment.to_s

        new_entry.json_fields["transfer_id"]    = ctx[:transfer_token]
        new_entry.json_fields["orig_amount"]    = entry.amount_cents
        new_entry.json_fields["orig_id"]        = entry.id
        new_entry.capital_commitment_id         = to_commitment.id
        new_entry.amount_cents                  = (orig_amount   * transfer_ratio).round(2)
        new_entry.folio_amount_cents            = (orig_folio    * transfer_ratio).round(2)
        new_entry.tracking_amount_cents         = (orig_tracking * transfer_ratio).round(2)
        new_entry.created_at = Time.zone.now
        new_entry.updated_at = Time.zone.now
        new_entry.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original entry ID: #{entry.id}. #{entry.amount_cents} * #{transfer_ratio} = #{new_entry.amount_cents}"

        entry.json_fields["transfer_id"]    = ctx[:transfer_token]
        entry.json_fields["orig_amount"]    = entry.amount_cents
        entry.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original entry ID: #{entry.id}"

        AccountEntry.transaction do
          entry.update_columns(
            amount_cents:          (orig_amount   * retained_ratio).round(2),
            folio_amount_cents:    (orig_folio    * retained_ratio).round(2),
            tracking_amount_cents: (orig_tracking * retained_ratio).round(2),
            json_fields:           entry.json_fields,
            updated_at:            Time.current
          )
          # Insert without callbacks
          AccountEntry.insert_all!([new_entry.attributes.except("generated_deleted")])
        end
      end
    end
    true
  end

  def transfer_remittances(ctx, **)
    from_commitment = ctx[:from_commitment]
    to_commitment   = ctx[:to_commitment]
    transfer_ratio  = ctx[:transfer_ratio]
    retained_ratio  = 1 - transfer_ratio
    token           = ctx[:transfer_token]

    from_commitment.capital_remittances.each do |remittance|
      orig_call              = BigDecimal(remittance.call_amount_cents.to_s)
      orig_collected         = BigDecimal(remittance.collected_amount_cents.to_s)
      orig_committed         = BigDecimal(remittance.committed_amount_cents.to_s)
      orig_folio_call        = BigDecimal(remittance.folio_call_amount_cents.to_s)
      orig_folio_collected   = BigDecimal(remittance.folio_collected_amount_cents.to_s)
      orig_folio_committed   = BigDecimal(remittance.folio_committed_amount_cents.to_s)
      orig_capital_fee       = BigDecimal(remittance.capital_fee_cents.to_s)
      orig_other_fee         = BigDecimal(remittance.other_fee_cents.to_s)
      orig_folio_capital_fee = BigDecimal(remittance.folio_capital_fee_cents.to_s)
      orig_folio_other_fee   = BigDecimal(remittance.folio_other_fee_cents.to_s)
      orig_computed          = BigDecimal(remittance.computed_amount_cents.to_s)
      orig_percentage        = BigDecimal(remittance.percentage.to_s)
      orig_arrear_folio      = BigDecimal(remittance.arrear_folio_amount_cents.to_s)
      orig_arrear            = BigDecimal(remittance.arrear_amount_cents.to_s)
      orig_tracking_collected = BigDecimal(remittance.tracking_collected_amount_cents.to_s)
      orig_tracking_call     = BigDecimal(remittance.tracking_call_amount_cents.to_s)

      new_remittance = remittance.dup
      new_remittance.json_fields["transfer_id"]           = ctx[:transfer_token]
      new_remittance.json_fields["orig_id"]               = remittance.id
      new_remittance.json_fields["orig_call_amount"]      = remittance.call_amount_cents
      new_remittance.json_fields["orig_collected_amount"] = remittance.collected_amount_cents
      new_remittance.json_fields["orig_committed_amount"] = remittance.committed_amount_cents
      new_remittance.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original remittance ID: #{remittance.id}"

      new_remittance.investor_id            = to_commitment.investor_id
      new_remittance.folio_id               = to_commitment.folio_id
      new_remittance.investor_name          = to_commitment.investor_name
      new_remittance.capital_commitment_id  = to_commitment.id
      new_remittance.call_amount_cents                  = (orig_call              * transfer_ratio).round(2)
      new_remittance.collected_amount_cents             = (orig_collected         * transfer_ratio).round(2)
      new_remittance.committed_amount_cents             = (orig_committed         * transfer_ratio).round(2)
      new_remittance.folio_call_amount_cents            = (orig_folio_call        * transfer_ratio).round(2)
      new_remittance.folio_collected_amount_cents       = (orig_folio_collected   * transfer_ratio).round(2)
      new_remittance.folio_committed_amount_cents       = (orig_folio_committed   * transfer_ratio).round(2)
      new_remittance.capital_fee_cents                  = (orig_capital_fee       * transfer_ratio).round(2)
      new_remittance.other_fee_cents                    = (orig_other_fee         * transfer_ratio).round(2)
      new_remittance.folio_capital_fee_cents            = (orig_folio_capital_fee * transfer_ratio).round(2)
      new_remittance.folio_other_fee_cents              = (orig_folio_other_fee   * transfer_ratio).round(2)
      new_remittance.computed_amount_cents              = (orig_computed          * transfer_ratio).round(2)
      new_remittance.percentage                         = (orig_percentage        * transfer_ratio).round(10)
      new_remittance.arrear_folio_amount_cents          = (orig_arrear_folio      * transfer_ratio).round(2)
      new_remittance.arrear_amount_cents                = (orig_arrear            * transfer_ratio).round(2)
      new_remittance.tracking_collected_amount_cents    = (orig_tracking_collected * transfer_ratio).round(2)
      new_remittance.tracking_call_amount_cents         = (orig_tracking_call     * transfer_ratio).round(2)
      new_remittance.created_at = Time.zone.now
      new_remittance.updated_at = Time.zone.now

      remittance.json_fields["transfer_id"]           = ctx[:transfer_token]
      remittance.json_fields["orig_call_amount"]      = remittance.call_amount_cents
      remittance.json_fields["orig_collected_amount"] = remittance.collected_amount_cents
      remittance.json_fields["orig_committed_amount"] = remittance.committed_amount_cents
      remittance.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original remittance ID: #{remittance.id}"

      remittance.call_amount_cents               = (orig_call              * retained_ratio).round(2)
      remittance.collected_amount_cents          = (orig_collected         * retained_ratio).round(2)
      remittance.committed_amount_cents          = (orig_committed         * retained_ratio).round(2)
      remittance.folio_call_amount_cents         = (orig_folio_call        * retained_ratio).round(2)
      remittance.folio_collected_amount_cents    = (orig_folio_collected   * retained_ratio).round(2)
      remittance.folio_committed_amount_cents    = (orig_folio_committed   * retained_ratio).round(2)
      remittance.capital_fee_cents               = (orig_capital_fee       * retained_ratio).round(2)
      remittance.other_fee_cents                 = (orig_other_fee         * retained_ratio).round(2)
      remittance.folio_capital_fee_cents         = (orig_folio_capital_fee * retained_ratio).round(2)
      remittance.folio_other_fee_cents           = (orig_folio_other_fee   * retained_ratio).round(2)
      remittance.computed_amount_cents           = (orig_computed          * retained_ratio).round(2)
      remittance.percentage                      = (orig_percentage        * retained_ratio).round(10)
      remittance.arrear_folio_amount_cents       = (orig_arrear_folio      * retained_ratio).round(2)
      remittance.arrear_amount_cents             = (orig_arrear            * retained_ratio).round(2)
      remittance.tracking_collected_amount_cents = (orig_tracking_collected * retained_ratio).round(2)
      remittance.tracking_call_amount_cents      = (orig_tracking_call     * retained_ratio).round(2)

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
        # Now get back the newly created remittance using the transfer_id
        scope = CapitalRemittance.where(capital_call_id: remittance.capital_call_id, capital_commitment_id: to_commitment.id)

        scope = case ActiveRecord::Base.connection.adapter_name
                when /Mysql/i # For prod / staging env
                  scope.where("json_fields ->> '$.\"transfer_id\"' = ?", token)
                when /SQLite/i # For the test env
                  # json_extract returns quoted JSON for strings; compare against JSON(value)
                  scope
                .where(<<~SQL.squish, token)
                  CASE
                    WHEN json_valid(json_fields)
                      THEN json_extract(json_fields, '$."transfer_id"')
                    ELSE NULL
                  END = ?
                SQL
                else # PostgreSQL, etc.
                  scope.where("json_fields ->> 'transfer_id' = ?", token)
                end

        new_remittance_id = scope.pick(:id) # Rails 7+: returns a single value

        # Now adjust the capital_remittance_payments
        remittance.capital_remittance_payments.each do |payment|
          orig_amount   = BigDecimal(payment.amount_cents.to_s)
          orig_folio    = BigDecimal(payment.folio_amount_cents.to_s)
          orig_tracking = BigDecimal(payment.tracking_amount_cents.to_s)

          new_payment = payment.dup
          new_payment.json_fields["transfer_id"]    = ctx[:transfer_token]
          new_payment.json_fields["orig_amount"]    = payment.amount_cents
          new_payment.json_fields["orig_id"]        = payment.id
          new_payment.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original payment ID: #{payment.id}"

          new_payment.investor_id             = to_commitment.investor_id
          new_payment.capital_remittance_id   = new_remittance_id
          new_payment.amount_cents            = (orig_amount   * transfer_ratio).round(2)
          new_payment.folio_amount_cents      = (orig_folio    * transfer_ratio).round(2)
          new_payment.tracking_amount_cents   = (orig_tracking * transfer_ratio).round(2)
          new_payment.created_at = Time.zone.now
          new_payment.updated_at = Time.zone.now

          CapitalRemittancePayment.insert_all([new_payment.attributes])

          payment.json_fields["transfer_id"]    = ctx[:transfer_token]
          payment.json_fields["orig_amount"]    = payment.amount_cents
          payment.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}"

          payment.update_columns(
            amount_cents:          (orig_amount   * retained_ratio).round(2),
            folio_amount_cents:    (orig_folio    * retained_ratio).round(2),
            tracking_amount_cents: (orig_tracking * retained_ratio).round(2),
            json_fields:           payment.json_fields
          )
        end
      end
    end

    true
  end

  def transfer_distributions(ctx, from_commitment:, to_commitment:, **)
    transfer_ratio = ctx[:transfer_ratio]
    retained_ratio = 1 - transfer_ratio

    from_commitment.capital_distribution_payments.each do |payment|
      orig_gross_payable                  = BigDecimal(payment.gross_payable_cents.to_s)
      orig_units_quantity                 = BigDecimal(payment.units_quantity.to_s)
      orig_income                         = BigDecimal(payment.income_cents.to_s)
      orig_percentage                     = BigDecimal(payment.percentage.to_s)
      orig_cost_of_investment             = BigDecimal(payment.cost_of_investment_cents.to_s)
      orig_folio_amount                   = BigDecimal(payment.folio_amount_cents.to_s)
      orig_net_of_account_entries         = BigDecimal(payment.net_of_account_entries_cents.to_s)
      orig_net_payable                    = BigDecimal(payment.net_payable_cents.to_s)
      orig_income_with_fees               = BigDecimal(payment.income_with_fees_cents.to_s)
      orig_cost_of_investment_with_fees   = BigDecimal(payment.cost_of_investment_with_fees_cents.to_s)
      orig_reinvestment                   = BigDecimal(payment.reinvestment_cents.to_s)
      orig_reinvestment_with_fees         = BigDecimal(payment.reinvestment_with_fees_cents.to_s)
      orig_gross_of_account_entries       = BigDecimal(payment.gross_of_account_entries_cents.to_s)
      orig_tracking_net_payable           = BigDecimal(payment.tracking_net_payable_cents.to_s)
      orig_tracking_gross_payable         = BigDecimal(payment.tracking_gross_payable_cents.to_s)
      orig_tracking_reinvestment_with_fees = BigDecimal(payment.tracking_reinvestment_with_fees_cents.to_s)

      new_payment = payment.dup
      new_payment.json_fields["transfer_id"]          = ctx[:transfer_token]
      new_payment.json_fields["orig_id"]              = payment.id
      new_payment.json_fields["orig_gross_payable"]   = payment.gross_payable_cents
      new_payment.json_fields["orig_units_quantity"]  = payment.units_quantity
      new_payment.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, original payment ID: #{payment.id}"

      new_payment.investor_id           = to_commitment.investor_id
      new_payment.folio_id              = to_commitment.folio_id
      new_payment.investor_name         = to_commitment.investor_name
      new_payment.capital_commitment_id = to_commitment.id

      new_payment.income_cents                        = (orig_income                        * transfer_ratio).round(2)
      new_payment.percentage                          = (orig_percentage                    * transfer_ratio).round(10)
      new_payment.units_quantity                      = (orig_units_quantity                * transfer_ratio).round(10)
      new_payment.cost_of_investment_cents            = (orig_cost_of_investment            * transfer_ratio).round(2)
      new_payment.folio_amount_cents                  = (orig_folio_amount                  * transfer_ratio).round(2)
      new_payment.net_of_account_entries_cents        = (orig_net_of_account_entries        * transfer_ratio).round(2)
      new_payment.net_payable_cents                   = (orig_net_payable                   * transfer_ratio).round(2)
      new_payment.income_with_fees_cents              = (orig_income_with_fees              * transfer_ratio).round(2)
      new_payment.cost_of_investment_with_fees_cents  = (orig_cost_of_investment_with_fees  * transfer_ratio).round(2)
      new_payment.reinvestment_cents                  = (orig_reinvestment                  * transfer_ratio).round(2)
      new_payment.reinvestment_with_fees_cents        = (orig_reinvestment_with_fees        * transfer_ratio).round(2)
      new_payment.gross_payable_cents                 = (orig_gross_payable                 * transfer_ratio).round(2)
      new_payment.gross_of_account_entries_cents      = (orig_gross_of_account_entries      * transfer_ratio).round(2)
      new_payment.tracking_net_payable_cents          = (orig_tracking_net_payable          * transfer_ratio).round(2)
      new_payment.tracking_gross_payable_cents        = (orig_tracking_gross_payable        * transfer_ratio).round(2)
      new_payment.tracking_reinvestment_with_fees_cents = (orig_tracking_reinvestment_with_fees * transfer_ratio).round(2)
      new_payment.created_at = Time.zone.now
      new_payment.updated_at = Time.zone.now

      CapitalDistributionPayment.insert_all([new_payment.attributes])

      payment.json_fields["transfer_id"]          = ctx[:transfer_token]
      payment.json_fields["orig_gross_payable"]   = payment.gross_payable_cents
      payment.json_fields["orig_units_quantity"]  = payment.units_quantity
      payment.json_fields["transfer_notes"] = "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}"

      payment.update_columns(
        income_cents:                         (orig_income                        * retained_ratio).round(2),
        percentage:                           (orig_percentage                    * retained_ratio).round(10),
        units_quantity:                       (orig_units_quantity                * retained_ratio).round(10),
        cost_of_investment_cents:             (orig_cost_of_investment            * retained_ratio).round(2),
        folio_amount_cents:                   (orig_folio_amount                  * retained_ratio).round(2),
        net_of_account_entries_cents:         (orig_net_of_account_entries        * retained_ratio).round(2),
        net_payable_cents:                    (orig_net_payable                   * retained_ratio).round(2),
        income_with_fees_cents:               (orig_income_with_fees              * retained_ratio).round(2),
        cost_of_investment_with_fees_cents:   (orig_cost_of_investment_with_fees  * retained_ratio).round(2),
        reinvestment_cents:                   (orig_reinvestment                  * retained_ratio).round(2),
        reinvestment_with_fees_cents:         (orig_reinvestment_with_fees        * retained_ratio).round(2),
        gross_payable_cents:                  (orig_gross_payable                 * retained_ratio).round(2),
        gross_of_account_entries_cents:       (orig_gross_of_account_entries      * retained_ratio).round(2),
        tracking_net_payable_cents:           (orig_tracking_net_payable          * retained_ratio).round(2),
        tracking_gross_payable_cents:         (orig_tracking_gross_payable        * retained_ratio).round(2),
        tracking_reinvestment_with_fees_cents: (orig_tracking_reinvestment_with_fees * retained_ratio).round(2),
        json_fields: payment.json_fields
      )
    end
    true
  end

  def apply_commitment_adjustments(ctx, from_commitment:, to_commitment:, fund:, **)
    transfer_ratio    = ctx[:transfer_ratio]
    orig_folio_amount = BigDecimal(from_commitment.folio_committed_amount_cents.to_s)
    # Do NOT wrap in a transaction — CommitmentAdjustment uses counter_culture which fires after_commit

    to_ca = CommitmentAdjustment.new(
      fund_id: fund.id,
      entity_id: to_commitment.entity_id,
      capital_commitment_id: to_commitment.id,
      # amount_cents: orig_amount * transfer_ratio,
      folio_amount_cents: orig_folio_amount * transfer_ratio,
      adjustment_type: "Transfer",
      reason: "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, transfer_id: #{ctx[:transfer_token]}",
      transfer_date: ctx[:transfer_date],
      # Use transfer_date so the exchange rate reflects the transaction date, not the
      # seller's historical commitment date. This also removes the artificial constraint
      # that required the buyer to have joined the fund before or on the seller's date.
      as_of: ctx[:transfer_date]
    )

    return false unless AdjustmentCreate.call(commitment_adjustment: to_ca).success?

    from_ca = CommitmentAdjustment.new(
      fund_id: fund.id,
      entity_id: from_commitment.entity_id,
      capital_commitment_id: from_commitment.id,
      # amount_cents: -orig_amount * transfer_ratio,
      folio_amount_cents: -orig_folio_amount * transfer_ratio,
      adjustment_type: "Transfer",
      reason: "Transfer from #{from_commitment.folio_id} to #{to_commitment.folio_id}, transfer_ratio: #{transfer_ratio}, transfer_id: #{ctx[:transfer_token]}",
      transfer_date: ctx[:transfer_date],
      as_of: ctx[:transfer_date]
    )

    result = AdjustmentCreate.call(commitment_adjustment: from_ca)

    result.success?
  end

  def counter_culture_fix_counts(_ctx, fund:, **)
    CapitalRemittancePayment.counter_culture_fix_counts where: { 'capital_remittance_payments.fund_id': fund.id }
    CapitalRemittance.counter_culture_fix_counts where: { 'capital_remittances.fund_id': fund.id }
    CapitalDistributionPayment.counter_culture_fix_counts where: { 'capital_distribution_payments.fund_id': fund.id }
    FundUnit.counter_culture_fix_counts where: { 'fund_units.fund_id': fund.id }
    CapitalCommitment.counter_culture_fix_counts where: { 'capital_commitments.fund_id': fund.id }
    CommitmentAdjustment.counter_culture_fix_counts where: { 'commitment_adjustments.fund_id': fund.id }
    true
  end

  def completed(_ctx, transfer:, **)
    transfer.status = "completed"
    transfer.save
    true
  end
end
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/BlockLength
# rubocop:enable Rails/SkipsModelValidations
