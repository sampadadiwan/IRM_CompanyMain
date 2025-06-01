module CapitalRemittanceCallBasis
  extend ActiveSupport::Concern

  # Computes the call amount as a percentage of the commitment amount.
  # The percentage is derived from the fund's closing percentages.
  def call_basis_percentage_commitment
    # Determine the applicable percentage from capital call's close percentages.
    self.percentage = if capital_call.close_percentages&.dig(capital_commitment.fund_close).present?
                        capital_call.close_percentages[capital_commitment.fund_close].to_d
                      else
                        BigDecimal(0)
                      end

    # Calculate the folio's portion of the call amount in its currency.
    self.folio_call_amount_cents = percentage * capital_commitment.folio_committed_amount_cents / 100.0

    # Convert FX
    self.computed_amount_cents = convert_currency(
      capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, remittance_date
    )

    # Include capital fees in both folio and fund currency calculations.
    self.folio_call_amount_cents += folio_capital_fee_cents
    self.call_amount_cents = computed_amount_cents + capital_fee_cents

    logger.error "call_basis_percentage: computed_amount_cents = #{computed_amount_cents}, \
                  call_amount_cents = #{call_amount_cents}, \
                  folio_call_amount_cents = #{folio_call_amount_cents} \
                  for #{capital_commitment} in #{capital_call}"
  end

  # Computes the call amount based on a specific account entry, such as
  # "Investable Capital Percentage" or "Foreign Investable Capital Percentage".
  def call_basis_account_entry(account_entry_name)
    # Fetch the latest applicable account entry for the commitment before the due date.
    ae = capital_commitment.account_entries.where(
      name: account_entry_name, reporting_date: ..capital_call.due_date
    ).order(reporting_date: :desc).first

    # Assign the percentage from the account entry or default to zero.
    self.percentage = ae&.amount_cents || 0

    # Log the result for debugging purposes.
    if ae.nil?
      logger.error "No #{account_entry_name} found for #{capital_commitment} in #{capital_call}"
    else
      logger.error "#{ae.amount_cents} found for #{capital_commitment} in #{capital_call.to_json}"
    end

    # Compute the call amount based on the retrieved percentage.
    self.computed_amount_cents = capital_call.amount_to_be_called_cents * percentage / 100.0
    self.call_amount_cents = computed_amount_cents + capital_fee_cents

    # Convert FX
    self.folio_call_amount_cents = convert_currency(
      fund.currency, capital_commitment.folio_currency, call_amount_cents, remittance_date
    )

    # Log computation details for auditing purposes.
    logger.error "call_basis_account_entry: computed_amount_cents = #{computed_amount_cents}, \
                  call_amount_cents = #{call_amount_cents}, \
                  folio_call_amount_cents = #{folio_call_amount_cents} \
                  for #{capital_commitment} in #{capital_call}"
  end

  # Computes the call amount based on an uploaded remittance.
  # This method assumes the folio_call_amount already includes capital fees.
  def call_basis_upload
    # Convert the adjusted folio call amount to the fund's currency.
    if call_amount_cents.zero?
      self.call_amount_cents = convert_currency(
        capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, remittance_date
      )
    end

    self.computed_amount_cents = call_amount_cents - capital_fee_cents

    # Calculate the percentage of the committed folio amount that is being called.
    self.percentage = [(folio_call_amount_cents / capital_commitment.folio_committed_amount_cents) * 100.0, 100.0].min
    # if percentage is less than -100 then limit to -100.0
    self.percentage = -100.0 if percentage < -100.0
    logger.error "call_basis_upload: computed_amount_cents = #{computed_amount_cents}, \
                  call_amount_cents = #{call_amount_cents}, \
                  folio_call_amount_cents = #{folio_call_amount_cents} \
                  for #{capital_commitment} in #{capital_call}"
  end
end
