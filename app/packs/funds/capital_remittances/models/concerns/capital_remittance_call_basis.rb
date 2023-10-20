module CapitalRemittanceCallBasis
  extend ActiveSupport::Concern

  def call_basis_percentage_commitment
    self.percentage = capital_call.percentage_called
    self.folio_call_amount_cents = percentage * capital_commitment.folio_committed_amount_cents / 100.0

    # Now compute the call amount in the fund currency.
    self.computed_amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, payment_date)

    # Now add the capital fees
    self.folio_call_amount_cents += folio_capital_fee_cents
    self.call_amount_cents = computed_amount_cents + capital_fee_cents
  end

  # Example Investable Capital Percentage or Foreign Investable Capital Percentage
  def call_basis_account_entry(account_entry_name)
    # Get the percentage from the account_entry
    ae = capital_commitment.account_entries.where(name: account_entry_name, reporting_date: ..capital_call.due_date).order(reporting_date: :desc).first
    self.percentage = ae&.amount_cents || 0

    if ae.nil?
      logger.error "No #{account_entry_name} found for #{capital_commitment} for #{capital_call}"
    else
      logger.error "#{ae.amount_cents} found for #{capital_commitment} for #{capital_call.to_json}"
    end

    self.computed_amount_cents = capital_call.amount_to_be_called_cents * percentage / 100.0

    self.call_amount_cents = computed_amount_cents + capital_fee_cents

    # Now compute the folio call amount in the folio currency.
    self.folio_call_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency, call_amount_cents, payment_date)

    logger.error "call_basis_account_entry: computed_amount_cents = #{computed_amount_cents}, call_amount_cents = #{call_amount_cents}, folio_call_amount_cents = #{folio_call_amount_cents} found for #{capital_commitment} for #{capital_call}"
  end

  def call_basis_upload
    # This is for direct upload of remittances, where the folio_call_amount includes the capital fees
    self.folio_call_amount_cents -= folio_capital_fee_cents

    # Now compute the call amount in the fund currency.
    self.computed_amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, payment_date)

    # Now add the capital fees
    self.folio_call_amount_cents += folio_capital_fee_cents
    self.percentage = self.folio_call_amount_cents / capital_commitment.folio_committed_amount_cents * 100.0
    self.call_amount_cents = computed_amount_cents + capital_fee_cents
  end
end
