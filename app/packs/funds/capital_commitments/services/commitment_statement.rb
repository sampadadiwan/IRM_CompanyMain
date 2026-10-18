# One folio's money in one answer: its remittances (what was called, collected and is due per call),
# the payments against them, its distribution payments, and its ledger totals by entry type.
#
# Reads only, and only what the statement shows: explicit columns for the small lists, and a
# grouped SUM for the ledger, so a folio with tens of thousands of account entries never loads them
# (CLAUDE.md large-table rules).
#
# openspec/changes/funds-json-api-hardening — design card ⑦, worked examples H9 E12 E13.
class CommitmentStatement
  Result = Struct.new(:capital_commitment, :remittances, :remittance_payments, :distribution_payments,
                      :ledger_totals, keyword_init: true)

  def self.call(capital_commitment)
    new(capital_commitment).call
  end

  def initialize(capital_commitment)
    @commitment = capital_commitment
  end

  def call
    Result.new(capital_commitment: @commitment, remittances:, remittance_payments:, distribution_payments:,
               ledger_totals:)
  end

  private

  # Per call: called, collected and due (fund currency), with the call's name and dates
  def remittances
    @commitment.capital_remittances.joins(:capital_call)
               .select("capital_remittances.id, capital_remittances.capital_call_id, capital_remittances.status,
                        capital_remittances.call_amount_cents, capital_remittances.collected_amount_cents,
                        capital_remittances.folio_call_amount_cents, capital_remittances.folio_collected_amount_cents,
                        capital_calls.name AS call_name, capital_calls.call_date, capital_calls.due_date")
               .order("capital_calls.call_date, capital_remittances.id")
  end

  def remittance_payments
    CapitalRemittancePayment.where(capital_remittance_id: @commitment.capital_remittances.select(:id))
                            .select(:id, :capital_remittance_id, :payment_date, :amount_cents, :folio_amount_cents, :reference_no)
                            .order(:payment_date, :id)
  end

  def distribution_payments
    @commitment.capital_distribution_payments
               .select(:id, :capital_distribution_id, :payment_date, :completed, :income_cents, :net_payable_cents, :folio_amount_cents)
               .order(:payment_date, :id)
  end

  # E13: entry type → total (fund currency, major units) — one grouped query, never the rows
  def ledger_totals
    AccountEntry.where(capital_commitment_id: @commitment.id, fund_id: @commitment.fund_id)
                .group(:entry_type).sum(:amount_cents)
                .transform_values { |cents| cents.to_f / 100 }
  end
end
